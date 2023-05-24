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


public class NetworkSession {

  public var isClosed: Bool { closed }

  internal let session: URLSession
  internal let delegate: NetworkSessionDelegate // swiftlint:disable:this weak_delegate
  internal let serverTrustPolicyManager: ServerTrustPolicyManager?

  private var taskDelegates: [URLSessionTask: URLSessionTaskDelegate] = [:]
  private let taskDelegatesLockQueue = DispatchQueue(label: "NetworkSession.taskDelegates Lock")
  private let taskDelegateOperaionQueue = OperationQueue()
  private var closed = false

  public init(
    configuration: URLSessionConfiguration,
    serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
    delegate externalDelegate: URLSessionDelegate? = nil
  ) {
    delegate = NetworkSessionDelegate(delegate: externalDelegate)
    session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: taskDelegateOperaionQueue)
    self.serverTrustPolicyManager = serverTrustPolicyManager
    delegate.owner = self
  }

  public func copy(
    configuration: URLSessionConfiguration? = nil,
    serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
    delegate externalDelegate: URLSessionDelegate? = nil
  ) -> NetworkSession {

    return NetworkSession(
      configuration: configuration ?? self.session.configuration,
      serverTrustPolicyManager: serverTrustPolicyManager ?? self.serverTrustPolicyManager,
      delegate: externalDelegate ?? self.delegate.delegate
    )
  }

  internal func getTaskDelegates() -> [URLSessionTaskDelegate] {
    taskDelegatesLockQueue.sync { Array(taskDelegates.values) }
  }

  internal func getTaskDelegate(for task: URLSessionTask) -> URLSessionTaskDelegate? {
    taskDelegatesLockQueue.sync { taskDelegates[task] }
  }

  internal func setTaskDelegate(_ delegate: URLSessionTaskDelegate, for task: URLSessionTask) {
    taskDelegatesLockQueue.sync { taskDelegates[task] = delegate }
  }

  internal func removeTaskDelegate(for task: URLSessionTask) -> URLSessionTaskDelegate? {
    taskDelegatesLockQueue.sync { taskDelegates.removeValue(forKey: task) }
  }

  public func data(for request: URLRequest) async throws -> (Data?, URLResponse) {

    if closed {
      throw URLError(.cancelled)
    }

    return try await withUnsafeThrowingContinuation { continuation in
      let task = session.dataTask(with: request)
      setTaskDelegate(DataDelegate(continuation: continuation), for: task)
      task.resume()
    }
  }

  public func validatedData(for request: URLRequest) async throws -> (Data?, HTTPURLResponse) {

    let (data, response) = try await data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    if 400 ..< 600 ~= httpResponse.statusCode {
      throw SundayError.responseValidationFailed(reason: .unacceptableStatusCode(
        response: httpResponse,
        data: data
      ))
    }

    return (data, httpResponse)
  }

  public enum DataEvent {
    case connect(HTTPURLResponse)
    case data(Data)
  }

  public typealias DataEventStream = AsyncThrowingStream<NetworkSession.DataEvent, Error>

  public func dataEventStream(for request: URLRequest) throws -> DataEventStream {

    if closed {
      throw URLError(.cancelled)
    }

    return AsyncThrowingStream(DataEvent.self) {

      let task = session.dataTask(with: request)

      setTaskDelegate(DataStreamDelegate(continuation: $0), for: task)

      $0.onTermination = { _ in task.cancel() }

      task.resume()
    }

  }

  public func close(cancelOutstandingTasks: Bool) {
    if cancelOutstandingTasks {
      session.invalidateAndCancel()
    }
    else {
      session.finishTasksAndInvalidate()
    }
    closed = true
  }

}

private final class DataDelegate: NSObject, URLSessionDataDelegate {

  let continuation: UnsafeContinuation<(Data?, URLResponse), Error>
  var response: URLResponse?
  var data: Data?

  init(continuation: UnsafeContinuation<(Data?, URLResponse), Error>) {
    self.continuation = continuation
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error {
      continuation.resume(throwing: error)
      return
    }
    guard let response = response else {
      continuation.resume(throwing: URLError(.unknown))
      return
    }
    continuation.resume(returning: (data, response))
  }

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {

    self.response = response

    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    if self.data == nil {
      self.data = data
    }
    else {
      self.data!.append(data)
    }
  }

}

private final class DataStreamDelegate: NSObject, URLSessionDataDelegate {

  let continuation: NetworkSession.DataEventStream.Continuation

  init(continuation: NetworkSession.DataEventStream.Continuation) {
    self.continuation = continuation
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    continuation.finish(throwing: error)
  }

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {

    guard let httpResponse = response as? HTTPURLResponse else {
      continuation.finish(throwing: SundayError.invalidHTTPResponse)
      completionHandler(.cancel)
      return
    }

    if 400 ..< 600 ~= httpResponse.statusCode {
      let error = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(
        response: httpResponse,
        data: nil
      ))
      continuation.finish(throwing: error)
      completionHandler(.cancel)
      return
    }

    continuation.yield(.connect(httpResponse))

    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    continuation.yield(.data(data))
  }

}
