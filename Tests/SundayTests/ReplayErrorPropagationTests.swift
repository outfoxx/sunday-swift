/*
 * Copyright 2026 Outfox, Inc.
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
import SundayServer
import Synchronization
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ReplayErrorPropagationTests {
  private final class Stop: RequestCancellationError {}

  private final class Replacement: RequestAdapter {
    let calls = Mutex(0)
    let stop: Stop

    init(stop: Stop) { self.stop = stop }

    func adapt(request: URLRequest) throws -> URLRequest {
      try request.with(streamingBody: StreamingBody(stream: {
        let count = self.calls.withLock { $0 += 1; return $0 }
        if count > 1 { throw self.stop }
        return InputStream(data: Data("replacement".utf8))
      }))
    }
  }

  private final class AuthenticationDelegate: NSObject, URLSessionTaskDelegate {
    let bodyDelegate: any URLSessionTaskDelegate

    init(bodyDelegate: any URLSessionTaskDelegate) { self.bodyDelegate = bodyDelegate }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
      completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
      guard challenge.previousFailureCount == 0 else {
        completionHandler(.cancelAuthenticationChallenge, nil)
        return
      }
      completionHandler(.useCredential, URLCredential(user: "user", password: "password", persistence: .none))
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void
    ) {
      bodyDelegate.urlSession?(session, task: task, needNewBodyStream: completionHandler)
    }
  }

  @Test(arguments: [false, true])
  func adapterBodyReplayPreservesOriginalStopError(streaming: Bool) async throws {
    let requests = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { POST { request, response in
        requests.withLock { $0 += 1 }
        #expect(request.body == Data("replacement".utf8))
        response.send(status: .unauthenticated,
                      headers: ["WWW-Authenticate": ["Basic realm=\"replay\""]], body: Data())
      } }
    }
    let base = try await startTestServer(server)
    defer { server.stop() }

    // Exercise Sunday's native body replay implementation with a delegate that accepts the challenge.
    let bodySession = URLSession.sunday(configuration: .ephemeral)
    defer { bodySession.invalidateAndCancel() }
    let bodyDelegate = try #require(bodySession.delegate as? any URLSessionTaskDelegate)
    let delegate = AuthenticationDelegate(bodyDelegate: bodyDelegate)
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    let stop = Stop()
    let adapter = Replacement(stop: stop)
    let transport = URLSessionTransport(baseURL: .init(format: base.absoluteString), session: session,
                                        eventSession: session, requestAdapter: adapter)
    defer { transport.close() }
    let spec = OperationSpec.streaming(method: .post, pathTemplate: "/value",
                                      body: StreamingBody(stream: { InputStream(data: Data("original".utf8)) }),
                                      contentTypes: [.octetStream])
    do {
      if streaming {
        let stream = transport.eventStream(spec: spec) { _, _, _, data, _ in data }
        for try await _ in stream { Issue.record("Unexpected event") }
      }
      else { try await transport.result(spec: spec) }
      Issue.record("Expected the body factory's stop error")
    }
    catch { #expect((error as? Stop) === stop) }
    #expect(adapter.calls.withLock { $0 } == 2)
    #expect(requests.withLock { $0 } == 1)
  }
}
