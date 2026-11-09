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
@testable import Sunday
@testable import SundayServer
import Synchronization
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct RedirectOwnershipTests {
  private final class Delegate: NSObject, URLSessionTaskDelegate {
    let action: @Sendable (URLRequest) -> URLRequest?
    init(action: @escaping @Sendable (URLRequest) -> URLRequest?) { self.action = action }
    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(action(request)) }
  }

  private struct Observer: RequestAdapter {
    let action: @Sendable (URLRequest) -> Void
    func adapt(request: URLRequest) -> URLRequest { action(request); return request }
  }

  private struct SeeOther: ResponseAdapter {
    func adapt(response: HTTPURLResponse, for request: URLRequest) throws -> HTTPURLResponse {
      guard request.url?.path == "/start" else { return response }
      return try response.clone(statusCode: 303).setting(header: "Location", value: "/end")
    }
  }

  @Test(arguments: [false, true])
  func forwardedRedirectRunsOnSessionDelegateQueue(mainQueue: Bool) async throws {
    let queue = mainQueue ? OperationQueue.main : OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let called = Mutex(false)
    let delegate = Delegate { request in
      #expect(OperationQueue.current === queue)
      if mainQueue { #expect(Thread.isMainThread) }
      called.withLock { $0 = true }
      return request.setting(header: "X-Delegate", value: "accepted")
    }
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: queue)
    let request = URLRequest(url: URL(string: "https://example.test/start")!)
    let task = session.dataTask(with: request)
    defer { task.cancel(); session.invalidateAndCancel() }
    let attempt = URLSessionRequestAttempt(request: request, delegate: delegate)
    attempt.attach(task: task)
    let response = HTTPURLResponse(url: request.url!, statusCode: 307, httpVersion: nil, headerFields: nil)!
    let accepted = try await attempt.redirect(in: session, response: response, proposed: request)
    #expect(accepted?.value(forHTTPHeaderField: "X-Delegate") == "accepted")
    #expect(called.withLock { $0 })
  }

  private final class PendingDelegate: NSObject, URLSessionTaskDelegate {
    let callback = NativeTaskResult<@Sendable (URLRequest?) -> Void>()
    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      #expect(OperationQueue.current === session.delegateQueue)
      callback.complete(.success(completionHandler))
    }
  }

  @Test func cancellingRedirectIgnoresLateDelegateCompletion() async throws {
    let delegate = PendingDelegate()
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: OperationQueue())
    let request = URLRequest(url: URL(string: "https://example.test/start")!)
    let nativeTask = session.dataTask(with: request)
    defer { nativeTask.cancel(); session.invalidateAndCancel() }
    let attempt = URLSessionRequestAttempt(request: request, delegate: delegate)
    attempt.attach(task: nativeTask)
    let response = HTTPURLResponse(url: request.url!, statusCode: 307, httpVersion: nil, headerFields: nil)!
    let task = Task { try await attempt.redirect(in: session, response: response, proposed: request) }
    let complete = try await delegate.callback.value()
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    complete(request)
  }

  @Test func redirectUsesTheWholeDelegateRequestIncludingBodyAndNativeSettings() async throws {
    let sent = Mutex(false)
    let replacement = Data("delegate supplied body".utf8)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/start") { POST { _, response in
        response.send(status: .temporaryRedirect, headers: ["Location": ["/end"]], body: Data())
      } }
      Path("/end") { POST { request, response in
        #expect(request.body == replacement)
        sent.withLock { $0 = true }
        response.send(status: .noContent)
      } }
    }
    let base = try await startTestServer(server)
    let delegate = Delegate { request in
      request.clone {
        $0.httpBody = replacement
        $0.timeoutInterval = 123
        $0.cachePolicy = .reloadIgnoringLocalCacheData
        $0.httpShouldHandleCookies = false
        $0.allowsCellularAccess = false
        $0.mainDocumentURL = base.appendingPathComponent("document")
      }
    }
    let observer = Observer { request in
      if request.url?.path == "/end" {
        #expect(request.httpBody == replacement)
        #expect(request.timeoutInterval == 123)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(!request.httpShouldHandleCookies && !request.allowsCellularAccess)
        #expect(request.mainDocumentURL == base.appendingPathComponent("document"))
      }
    }
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    let transport = URLSessionTransport(baseURL: .init(format: base.absoluteString), session: session,
                                        eventSession: session, requestAdapter: observer)
    defer { transport.close(); server.stop() }
    try await transport.result(spec: OperationSpec(method: .post, pathTemplate: "/start",
                                                  body: Data("original".utf8), contentTypes: [.octetStream]))
    #expect(sent.withLock { $0 })
  }

  @Test(arguments: [200, 307], [false, true])
  func adaptedRedirectUsesOrdinarySeeOtherSemantics(originalStatus: Int, streaming: Bool) async throws {
    let reached = Mutex(false)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/start") { POST { _, response in
        response.send(status: originalStatus == 200 ? .ok : .temporaryRedirect,
                      headers: ["Location": ["/end"]], body: Data("discarded".utf8))
      } }
      Path("/end") { GET { request, response in
        #expect(request.body?.isEmpty ?? true)
        #expect(request.header(for: "Content-Type") == nil)
        reached.withLock { $0 = true }
        response.send(status: .ok, headers: ["Content-Type": ["text/event-stream"]],
                      body: Data("data: value\n\n".utf8))
      } }
    }
    let base = try await startTestServer(server)
    let transport = URLSessionTransport(baseURL: .init(format: base.absoluteString), responseAdapter: SeeOther())
    defer { transport.close(); server.stop() }
    let spec = OperationSpec(method: HTTP.Method.post, pathTemplate: "/start", body: Data("original".utf8),
                             contentTypes: [.octetStream])
    if streaming {
      let stream = transport.eventStream(spec: spec) { _, _, _, data, _ in data }
      for try await value in stream { #expect(value == "value"); break }
    }
    else { #expect(try await transport.transportResponse(spec: spec).statusCode == 200) }
    #expect(reached.withLock { $0 })
  }
}
