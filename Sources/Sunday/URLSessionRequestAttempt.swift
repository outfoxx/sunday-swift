/*
 * Copyright 2021 Outfox, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import Synchronization

// A native I/O bridge. Headers pause body delivery; the execution loop owns adaptation and policy.
final class URLSessionRequestAttempt: NSObject, URLSessionDataDelegate {
  private struct State {
    weak var task: URLSessionTask?
    var rejectedResponse: HTTPURLResponse?
    var disposition: (@Sendable (URLSession.ResponseDisposition) -> Void)?
    var data = Data()
    var completed = false
    var bodyAccepted = false
  }

  let request: URLRequest
  let isolatesCredentials: Bool
  private let delegate: (any URLSessionDelegate)?
  private let state = Mutex(State())
  private let headers = NativeTaskResult<URLResponse>()
  private let body = NativeTaskResult<Data>()

  init(request: URLRequest, delegate: (any URLSessionDelegate)?) {
    self.request = request
    self.delegate = delegate
    self.isolatesCredentials = !request.securityBindings.isEmpty ||
      request.value(forHTTPHeaderField: "Authorization") != nil || request.value(forHTTPHeaderField: "Cookie") != nil
  }

  var rejectedResponse: HTTPURLResponse? { state.withLock { $0.rejectedResponse } }

  func attach(task: URLSessionTask) {
    let completed = state.withLock { state in
      state.task = task
      return state.completed
    }
    if completed { task.cancel() }
  }

  func receiveHeaders(in session: URLSession) async throws -> URLResponse {
    let task = session.dataTask(with: request)
    task.delegate = self
    attach(task: task)
    task.resume()
    return try await headers.value()
  }

  func acceptBody() {
    let disposition: (@Sendable (URLSession.ResponseDisposition) -> Void)? = state.withLock { state in
      guard !state.completed else { return nil }
      state.bodyAccepted = true
      defer { state.disposition = nil }
      return state.disposition
    }
    disposition?(.allow)
  }

  func collectBody() async throws -> Data {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await body.value()
    } onCancel: { self.cancel() }
  }

  func cancel() {
    let task = state.withLock { $0.task }
    finish(error: CancellationError(), response: nil)
    task?.cancel()
  }

  private func finish(error: (any Error)?, response: URLResponse?) {
    let completed = state.withLock { state -> State? in
      guard !state.completed else { return nil }
      let completed = state
      state.completed = true
      state.data = Data()
      state.disposition = nil
      return completed
    }
    guard let completed else { return }
    if let error, isRequestCancellation(error) {
      headers.complete(.failure(error))
      body.complete(.failure(error))
    }
    else if let rejected = completed.rejectedResponse {
      headers.complete(.success(rejected))
      body.complete(.success(Data()))
    }
    else if let error {
      headers.complete(.failure(error))
      body.complete(.failure(error))
    }
    else if let response {
      headers.complete(.success(response))
      body.complete(.success(completed.data))
    }
    else {
      headers.complete(.failure(URLError(.badServerResponse)))
      body.complete(.failure(URLError(.badServerResponse)))
    }
    completed.disposition?(.cancel)
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    let disposition = state.withLock { state -> URLSession.ResponseDisposition? in
      if state.completed { return .cancel }
      if state.bodyAccepted { return .allow }
      state.disposition = completionHandler
      return nil
    }
    headers.complete(.success(response))
    if let disposition { completionHandler(disposition) }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    state.withLock { if !$0.completed { $0.data.append(data) } }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    finish(error: error, response: task.response)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    // Return the response to the execution loop before considering redirects.
    completionHandler(nil)
  }

  func redirect(in session: URLSession, response: HTTPURLResponse, proposed: URLRequest) async throws -> URLRequest? {
    guard let task = state.withLock({ $0.task }) else { throw URLError(.cancelled) }
    let result = NativeTaskResult<URLRequest?>()
    let callback = BlockOperation {
      self.forwardRedirect(session, task: task, response: response, request: proposed) { result.complete(.success($0)) }
    }
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      session.delegateQueue.addOperation(callback)
      return try await result.value()
    } onCancel: {
      callback.cancel()
      result.complete(.failure(CancellationError()))
    }
  }

  private func forwardRedirect(
    _ session: URLSession, task: URLSessionTask, response: HTTPURLResponse, request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    if let delegate = delegate as? any URLSessionTaskDelegate,
       delegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(
         _:task:willPerformHTTPRedirection:newRequest:completionHandler:
       ))) {
      delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response,
                           newRequest: request, completionHandler: completionHandler)
    }
    else { completionHandler(request) }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void
  ) {
    if let delegate = delegate as? any URLSessionTaskDelegate,
       delegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:needNewBodyStream:))) {
      delegate.urlSession?(session, task: task, needNewBodyStream: completionHandler)
    }
    else { completionHandler(nil) }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    if isolatesCredentials, challenge.protectionSpace.authenticationMethod != NSURLAuthenticationMethodServerTrust {
      state.withLock { $0.rejectedResponse = challenge.failureResponse as? HTTPURLResponse }
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    if let delegate = delegate as? any URLSessionTaskDelegate,
       delegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:))) {
      delegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }
    else if let delegate,
            delegate.responds(to: #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))) {
      delegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
    }
    else { completionHandler(.performDefaultHandling, nil) }
  }
}
