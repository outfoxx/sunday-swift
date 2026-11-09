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
struct AdapterCompositionTests {
  private final class Stop: RequestCancellationError {}

  private struct Outbound: RequestAdapter {
    let action: @Sendable (URLRequest) async throws -> URLRequest
    func adapt(request: URLRequest) async throws -> URLRequest { try await action(request) }
  }

  private struct Inbound: ResponseAdapter {
    let action: @Sendable (HTTPURLResponse, URLRequest) async throws -> HTTPURLResponse
    func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
      try await action(response, request)
    }
  }

  private final class Both: RequestAdapter, ResponseAdapter {
    let requests = Mutex(0)
    let responses = Mutex(0)
    func adapt(request: URLRequest) -> URLRequest { requests.withLock { $0 += 1 }; return request }
    func adapt(response: HTTPURLResponse, for request: URLRequest) -> HTTPURLResponse {
      responses.withLock { $0 += 1 }; return response
    }
  }

  @Test(arguments: [false, true])
  func slotsNeverInferTheOtherProtocol(requestOnly: Bool) async throws {
    let adapter = Both()
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { _, response in response.send(status: .noContent) } }
    }
    let base = try await startTestServer(server)
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString),
      requestAdapter: requestOnly ? adapter : nil, responseAdapter: requestOnly ? nil : adapter
    )
    defer { transport.close(); server.stop() }
    try await transport.result(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/value"))
    #expect(adapter.requests.withLock { $0 } == (requestOnly ? 1 : 0))
    #expect(adapter.responses.withLock { $0 } == (requestOnly ? 0 : 1))
  }

  @Test func chainsPreserveTransformationsAndOrder() async throws {
    func outbound(_ value: String) -> Outbound {
      Outbound { request in
        var result = request
        result.setValue((request.value(forHTTPHeaderField: "X-Order") ?? "") + value, forHTTPHeaderField: "X-Order")
        return result
      }
    }
    func inbound(_ value: String) -> Inbound {
      Inbound { response, _ in
        HTTPURLResponse(url: response.url!, statusCode: response.statusCode, httpVersion: nil,
                        headerFields: ["X-Order": (response.value(forHTTPHeaderField: "X-Order") ?? "") + value])!
      }
    }
    let request = URLRequest(url: URL(string: "https://example.test")!)
    let requests = outbound("a").chain(to: outbound("b").chain(to: outbound("c"))).chain(to: outbound("d"))
    let adapted = try await requests.adapt(request: request)
    #expect(adapted.value(forHTTPHeaderField: "X-Order") == "abcd")
    let responses = inbound("a").chain(to: inbound("b").chain(to: inbound("c"))).chain(to: inbound("d"))
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    #expect(try await responses.adapt(response: response, for: adapted).value(forHTTPHeaderField: "X-Order") == "abcd")
  }

  @Test func chainStopsWithoutInvokingRemainingAdapters() async throws {
    let stop = Stop()
    let remaining = Mutex(0)
    let request = URLRequest(url: URL(string: "https://example.test")!)
    let requests = Outbound { _ in throw stop }.chain(to: Outbound { request in
      remaining.withLock { $0 += 1 }; return request
    })
    do {
      _ = try await requests.adapt(request: request)
      Issue.record("Expected stop")
    }
    catch { #expect((error as? Stop) === stop) }
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let responses = Inbound { _, _ in throw stop }.chain(to: Inbound { response, _ in
      remaining.withLock { $0 += 1 }; return response
    })
    do {
      _ = try await responses.adapt(response: response, for: request)
      Issue.record("Expected stop")
    }
    catch { #expect((error as? Stop) === stop) }
    #expect(remaining.withLock { $0 } == 0)
  }

  @Test func explicitAuthenticationAndObserverCompositionRefreshesNormalizedBearer() async throws {
    let refreshes = Mutex(0)
    let observed = Mutex<[Int]>([])
    let sent = Mutex<[String]>([])
    let authentication = RefreshingHeaderTokenAuthorizingAdapter(tokenHeaderType: "Bearer") {
      let value = refreshes.withLock { $0 += 1; return $0 }
      return TokenAuthorization(token: "token-\(value)", expires: .distantFuture)
    }
    let normalize = Outbound { request in
      var result = request
      let authorization = request.value(forHTTPHeaderField: "Authorization")?
        .replacingOccurrences(of: "Bearer ", with: "bearer   ")
      result.setValue(authorization, forHTTPHeaderField: "Authorization")
      return result
    }
    let observer = Inbound { response, _ in observed.withLock { $0.append(response.statusCode) }; return response }
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { request, response in
        let header = request.header(for: "Authorization") ?? ""
        sent.withLock { $0.append(header) }
        if header.contains("token-1") {
          response.send(status: .unauthenticated,
                        headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]], body: Data())
        }
        else { response.send(status: .noContent) }
      } }
    }
    let base = try await startTestServer(server)
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: authentication.chain(to: normalize),
      responseAdapter: authentication.chain(to: observer)
    )
    defer { transport.close(); server.stop() }
    try await transport.result(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/value"))
    #expect(refreshes.withLock { $0 } == 2)
    #expect(observed.withLock { $0 } == [401, 204])
    #expect(sent.withLock { $0 } == ["bearer   token-1", "bearer   token-2"])
  }

  @Test func normalizedBearerInvalidatesManagerAndStopsStaticAdapter() async throws {
    final class Provider: TokenProvider {
      let identity = "provider"
      let acquisitions = Mutex(0)
      func configure(_: SecurityBinding) -> TokenConfiguration { .init(clientIdentity: "client") }
      func acquire(_: TokenRequest) -> TokenSet {
        let value = acquisitions.withLock { $0 += 1; return $0 }
        return .init(accessToken: "token-\(value)")
      }
    }
    let binding = SecurityBinding(scheme: "identity", provider: "identity", flow: .clientCredentials,
                                  transport: .init(location: .header, name: "Authorization", prefix: "Bearer"))
    let manager = try TokenManager(provider: Provider())
    let authentication = AuthenticationAdapter(providers: ["identity": manager])
    let original = try URLRequest(url: URL(string: "https://example.test")!).withSecurity([binding])
    var first = try await authentication.adapt(request: original)
    first.setValue("bearer   token-1", forHTTPHeaderField: "Authorization")
    let rejected = HTTPURLResponse(url: original.url!, statusCode: 401, httpVersion: nil,
                                   headerFields: ["WWW-Authenticate": "Bearer error=invalid_token"])!
    _ = try await authentication.adapt(response: rejected, for: first)
    let next = try await authentication.adapt(request: original)
    #expect(next.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
    let fixed = HeaderTokenAuthorizingAdapter(tokenHeaderType: "Bearer", token: "token-1")
    await #expect(throws: TokenRejectedError.self) { try await fixed.adapt(response: rejected, for: first) }
    await manager.close()
  }

  @Test(arguments: [false, true])
  func redirectsPreserveBehaviorAndAdaptEveryAttempt(streaming: Bool) async throws {
    let events = Mutex<[String]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/redirect") { GET { _, response in
        response.send(status: .temporaryRedirect, headers: ["Location": ["/value"]], body: Data())
      } }
      Path("/value") { GET { request, response in
        #expect(request.header(for: "X-Once") == "x")
        response.send(status: .ok, headers: ["Content-Type": ["text/event-stream"]], body: Data("data: value\n\n".utf8))
      } }
    }
    let base = try await startTestServer(server)
    let outbound = Outbound { request in
      events.withLock { $0.append("request \(request.url!.path)") }
      var result = request
      result.setValue((request.value(forHTTPHeaderField: "X-Once") ?? "") + "x", forHTTPHeaderField: "X-Once")
      return result
    }
    let inbound = Inbound { response, request in
      events.withLock { $0.append("response \(response.statusCode) \(request.url!.path)") }
      return response
    }
    let transport = URLSessionTransport(baseURL: .init(format: base.absoluteString),
                                        requestAdapter: outbound, responseAdapter: inbound)
    defer { transport.close(); server.stop() }
    let spec = OperationSpec<Empty>(method: .get, pathTemplate: "/redirect")
    if streaming {
      let source = transport.eventSource(spec: spec)
      let (received, continuation) = AsyncStream<String>.makeStream()
      await source.setOnMessage { _, _, data in continuation.yield(data ?? ""); continuation.finish() }
      await source.connect()
      for await value in received { #expect(value == "value"); break }
      await source.close()
    }
    else { #expect(try await transport.transportResponse(spec: spec).statusCode == 200) }
    #expect(Array(events.withLock { $0 }.prefix(4)) == [
      "request /redirect", "response 307 /redirect", "request /value", "response 200 /value",
    ])
  }

  @Test func replacementStreamingFactoryReplaysOnlyReplacementBody() async throws {
    try await checkReplacementStreamingReplay(exported: false)
  }

  #if os(watchOS)
  @Test(.disabled("watchOS URLSession does not request replacement streams for native redirected uploads"))
  #else
  @Test
  #endif
  func exportedReplacementStreamingFactoryReplaysOnlyReplacementBody() async throws {
    try await checkReplacementStreamingReplay(exported: true)
  }

  private func checkReplacementStreamingReplay(exported: Bool) async throws {
    let bodies = Mutex<[Data]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/redirect") { POST { request, response in
        bodies.withLock { $0.append(request.body ?? Data()) }
        response.send(status: .temporaryRedirect, headers: ["Location": ["/value"]], body: Data())
      } }
      Path("/value") { POST { request, response in
        bodies.withLock { $0.append(request.body ?? Data()) }
        response.send(status: .noContent)
      } }
    }
    let base = try await startTestServer(server)
    let replacement = Data("replacement".utf8)
    let outbound = Outbound { request in
      try request.with(streamingBody: StreamingBody(stream: { InputStream(data: replacement) }))
    }
    let transport = URLSessionTransport(baseURL: .init(format: base.absoluteString), requestAdapter: outbound)
    defer { transport.close(); server.stop() }
    let spec = OperationSpec.streaming(method: .post, pathTemplate: "/redirect",
                                      body: StreamingBody(stream: { InputStream(data: Data("original".utf8)) }),
                                      contentTypes: [.octetStream])
    if exported {
      let request = try await transport.transportRequest(spec: spec)
      #expect(try await transport.transportResponse(request: request).statusCode == 204)
    }
    else { try await transport.result(spec: spec) }
    #expect(bodies.withLock { $0 } == [replacement, replacement])
  }

  @Test func replacingStreamWithoutFactoryDropsObsoleteReplayCapability() async throws {
    let request = try URLRequest(url: URL(string: "https://example.test")!).with(
      streamingBody: StreamingBody(stream: { InputStream(data: Data("original".utf8)) })
    )
    let adapted = try await adaptRequest(request, using: Outbound { request in
      var result = request
      result.httpBodyStream = InputStream(data: Data("replacement".utf8))
      return result
    })
    #expect(adapted.streamingBodyProperty == nil)
    #expect(adapted.httpBodyStream !== request.httpBodyStream)
  }

  @Test func bulkResponsePreservesLargePayloadAndAdaptsOnce() async throws {
    let body = Data((0 ..< 4 * 1024 * 1024).map { UInt8(truncatingIfNeeded: $0) })
    let responses = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { _, response in response.send(status: .ok, body: body) } }
    }
    let base = try await startTestServer(server)
    let inbound = Inbound { response, _ in responses.withLock { $0 += 1 }; return response }
    let transport = URLSessionTransport(baseURL: .init(format: base.absoluteString), responseAdapter: inbound)
    defer { transport.close(); server.stop() }
    let result: Data = try await transport.result(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/value"))
    #expect(result == body)
    #expect(responses.withLock { $0 } == 1)
  }

  @Test func cancellingBulkRequestCancelsSuspendedResponseAdapter() async throws {
    let (entered, continuation) = AsyncStream<Void>.makeStream()
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { _, response in response.send(status: .noContent) } }
    }
    let base = try await startTestServer(server)
    let adapter = Inbound { response, _ in
      continuation.yield(()); continuation.finish()
      try await Task.sleep(for: .seconds(60))
      return response
    }
    let transport = URLSessionTransport(baseURL: .init(format: base.absoluteString), responseAdapter: adapter)
    defer { transport.close(); server.stop() }
    let task = Task {
      try await transport.transportResponse(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/value"))
    }
    for await _ in entered { break }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
  private final class RedirectDelegate: NSObject, URLSessionTaskDelegate {
    let decision: @Sendable (URLRequest) -> URLRequest?
    init(decision: @escaping @Sendable (URLRequest) -> URLRequest?) { self.decision = decision }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      completionHandler(decision(request))
    }
  }

  @Test(arguments: ["follow", "veto", "stop"])
  func redirectAdaptationPrecedesNativePolicyAndPreservesItsDecision(mode: String) async throws {
    let order = Mutex<[String]>([])
    let stop = Stop()
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/redirect") { GET { _, response in
        response.send(status: .temporaryRedirect, headers: ["Location": ["/original"]], body: Data())
      } }
      Path("/changed") { GET { request, response in
        #expect(request.header(for: "X-Delegate") == "preserved")
        order.withLock { $0.append("send") }
        response.send(status: .noContent)
      } }
    }
    let base = try await startTestServer(server)
    let delegate = RedirectDelegate { request in
      order.withLock { $0.append("policy") }
      #expect(request.url?.path == "/changed")
      if mode == "veto" { return nil }
      var result = request
      result.setValue("preserved", forHTTPHeaderField: "X-Delegate")
      return result
    }
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    let adapter = Inbound { response, _ in
      guard response.statusCode == 307 else { return response }
      order.withLock { $0.append("adapt") }
      if mode == "stop" { throw stop }
      return HTTPURLResponse(url: response.url!, statusCode: 307, httpVersion: nil,
                             headerFields: ["Location": "/changed"])!
    }
    let transport = URLSessionTransport(baseURL: .init(format: base.absoluteString), session: session,
                                        eventSession: session, responseAdapter: adapter)
    defer { transport.close(); server.stop() }
    do {
      let response = try await transport.transportResponse(
        spec: OperationSpec<Empty>(method: .get, pathTemplate: "/redirect")
      )
      #expect(mode != "stop")
      #expect(response.statusCode == (mode == "veto" ? 307 : 204))
    }
    catch { #expect(mode == "stop"); #expect((error as? Stop) === stop) }
    let expected = mode == "stop" ? ["adapt"] : mode == "veto" ? ["adapt", "policy"] : ["adapt", "policy", "send"]
    #expect(order.withLock { $0 } == expected)
  }

}
