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
@testable import SundayServer
import Synchronization
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct RequestExecutionTests {
  private final class Stop: RequestCancellationError {
    let detail = UUID()
  }

  private struct Adapter: RequestAdapter, ResponseAdapter {
    var onRequest: @Sendable (URLRequest) async throws -> URLRequest = { $0 }
    var onResponse: @Sendable (HTTPURLResponse, URLRequest) async throws -> HTTPURLResponse = { response, _ in
      response
    }

    func adapt(request: URLRequest) async throws -> URLRequest { try await onRequest(request) }
    func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
      try await onResponse(response, request)
    }
  }

  private let binding = SecurityBinding(
    scheme: "identity", provider: "identity", flow: .clientCredentials,
    transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
  )

  private actor Provider: RefreshingTokenProvider {
    nonisolated let identity = "application"
    var acquisitions = 0
    var refreshes = 0
    nonisolated func configure(_: SecurityBinding) -> TokenConfiguration { .init(clientIdentity: "client") }
    func acquire(_: TokenRequest) -> TokenSet {
      acquisitions += 1
      return .init(accessToken: "initial", refreshToken: "refresh")
    }
    func refresh(_: TokenRequest, refreshToken: String) -> TokenSet {
      refreshes += 1
      return .init(accessToken: "renewed-\(refreshes)", refreshToken: refreshToken)
    }
  }

  @Test func adaptsEachAttemptFromOriginalAndReportsActualSentRequest() async throws {
    let order = Mutex<[String]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { request, response in
        let attempt = request.header(for: "X-Attempt") ?? ""
        order.withLock { $0.append("send-\(attempt)") }
        #expect(request.header(for: "X-Accumulated") == "x")
        if attempt == "1" {
          response.send(status: .unauthenticated,
                        headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]], body: Data())
        }
        else { response.send(status: .noContent) }
      } }
    }
    let base = try await startTestServer(server)
    let count = Mutex(0)
    let adapter = Adapter(onRequest: { original in
      let attempt = count.withLock { $0 += 1; return $0 }
      order.withLock { $0.append("adapt-\(attempt)") }
      var request = original
      request.setValue(String(attempt), forHTTPHeaderField: "X-Attempt")
      request.setValue("Bearer token-\(attempt)", forHTTPHeaderField: "Authorization")
      request.setValue((request.value(forHTTPHeaderField: "X-Accumulated") ?? "") + "x",
                       forHTTPHeaderField: "X-Accumulated")
      return request
    }, onResponse: { response, request in
      order.withLock { $0.append("response-\(request.value(forHTTPHeaderField: "X-Attempt") ?? "")") }
      return response
    })
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: adapter, responseAdapter: adapter
    )
    defer { server.stop(); transport.close() }
    await #expect(throws: (any Error).self) {
      try await transport.result(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/value"))
    }
    try await transport.result(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/value"))
    #expect(order.withLock { $0 } == ["adapt-1", "send-1", "response-1", "adapt-2", "send-2", "response-2"])
  }

  @Test(arguments: [false, true])
  func stopErrorEscapesUnchangedAndPreventsFurtherWork(fromResponse: Bool) async throws {
    let stop = Stop()
    let sent = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { _, response in
        sent.withLock { $0 += 1 }
        response.send(status: .unauthenticated,
                      headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]], body: Data())
      } }
    }
    let base = try await startTestServer(server)
    let adapter = Adapter(onRequest: { request in
      if !fromResponse { throw stop }
      return request
    }, onResponse: { _, _ in throw stop })
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: adapter, responseAdapter: adapter
    )
    defer { server.stop(); transport.close() }
    do {
      try await transport.result(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/value"))
      Issue.record("Expected the adapter to stop the operation")
    }
    catch { #expect((error as? Stop) === stop) }
    #expect(sent.withLock { $0 } == (fromResponse ? 1 : 0))
  }

  @Test func responseAdapterRunsBeforeStatusValidation() async throws {
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { _, response in response.send(status: .internalServerError) } }
    }
    let base = try await startTestServer(server)
    let adapter = Adapter(onResponse: { original, request in
      #expect(original.statusCode == 500)
      return HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
    })
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), responseAdapter: adapter
    )
    defer { server.stop(); transport.close() }
    try await transport.result(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/value"))
  }

  @Test func invalidatesEachExplicitAttemptWithoutHiddenRetries() async throws {
    let sent = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") {
        POST { _, response in
          sent.withLock { $0 += 1 }
          response.send(status: .unauthenticated,
                        headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]], body: Data())
        }
        GET { _, response in
          sent.withLock { $0 += 1 }
          response.send(status: .unauthenticated,
                        headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]], body: Data())
        }
      }
    }
    let base = try await startTestServer(server)
    let provider = Provider()
    let manager = try TokenManager(provider: provider)
    let authentication = AuthenticationAdapter(providers: ["identity": manager])
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: authentication, responseAdapter: authentication
    )
    defer { server.stop(); transport.close() }
    await #expect(throws: SundayError.self) {
      try await transport.transportResponse(spec: OperationSpec(
        method: .post, pathTemplate: "/value", body: "body", contentTypes: [.json], security: [binding]
      ))
    }
    #expect(sent.withLock { $0 } == 1)
    #expect(await provider.refreshes == 0)
    let get = OperationSpec<Empty>(method: .get, pathTemplate: "/value", security: [binding])
    let exported = try await transport.transportRequest(spec: get)
    #expect(exported.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-1")
    await #expect(throws: SundayError.self) { try await transport.transportResponse(spec: get) }
    #expect(sent.withLock { $0 } == 2)
    #expect(await provider.refreshes == 1)
    let next = try await transport.transportRequest(spec: get)
    #expect(next.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-2")
    await manager.close()
  }

  @Test func exportAdaptsOnceAndHasNoResponseLifecycle() async throws {
    let calls = Mutex<[String]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { request, response in
        #expect(request.header(for: "X-Adapted") == "yes")
        response.send(status: .noContent)
      } }
    }
    let base = try await startTestServer(server)
    let adapter = Adapter(onRequest: { request in
      calls.withLock { $0.append("request") }
      var result = request
      result.setValue("yes", forHTTPHeaderField: "X-Adapted")
      return result
    }, onResponse: { response, _ in calls.withLock { $0.append("response") }; return response })
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: adapter, responseAdapter: adapter
    )
    defer { server.stop(); transport.close() }
    let exported = try await transport.transportRequest(spec: OperationSpec<Empty>(
      method: .get, pathTemplate: "/value"
    ))
    #expect(exported.securityProperty == nil)
    _ = try await transport.transportResponse(request: exported)
    #expect(calls.withLock { $0 } == ["request"])
  }

  @Test(arguments: [false, true])
  func stopErrorTerminatesEventsWithoutReconnect(fromResponse: Bool) async throws {
    let stop = Stop()
    let sent = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") { GET { _, response in
        sent.withLock { $0 += 1 }
        response.send(status: .ok, headers: ["Content-Type": ["text/event-stream"]],
                      body: Data("data: value\n\n".utf8))
      } }
    }
    let base = try await startTestServer(server)
    let adapter = Adapter(onRequest: { request in
      if !fromResponse { throw stop }
      return request
    }, onResponse: { _, _ in throw stop })
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: adapter, responseAdapter: adapter
    )
    defer { server.stop(); transport.close() }
    let source = transport.eventSource(spec: OperationSpec<Empty>(method: .get, pathTemplate: "/events"))
    let (errors, continuation) = AsyncStream<any Error>.makeStream()
    await source.setOnStateError { error, state in
      if let error, state == .closed { continuation.yield(error); continuation.finish() }
    }
    await source.connect()
    for await error in errors { #expect((error as? Stop) === stop) }
    #expect(await source.readyState == .closed)
    #expect(await source.retryAttempt == 0)
    #expect(sent.withLock { $0 } == (fromResponse ? 1 : 0))
    await source.close()
  }

  @Test func refreshingHeaderAdapterInvalidatesOnlyTheRejectedValue() async throws {
    let count = Mutex(0)
    let adapter = RefreshingHeaderTokenAuthorizingAdapter(tokenHeaderType: "Bearer") {
      let value = count.withLock { $0 += 1; return $0 }
      return TokenAuthorization(token: String(value), expires: .distantFuture)
    }
    let original = URLRequest(url: URL(string: "https://api.example/value")!)
    let first = try await adapter.adapt(request: original)
    let rejected = HTTPURLResponse(
      url: original.url!, statusCode: 401, httpVersion: nil,
      headerFields: ["WWW-Authenticate": "Bearer error=invalid_token"]
    )!
    _ = try await adapter.adapt(response: rejected, for: first)
    let second = try await adapter.adapt(request: original)
    _ = try await adapter.adapt(response: rejected, for: first)
    let third = try await adapter.adapt(request: original)
    #expect(second.value(forHTTPHeaderField: "Authorization") == "Bearer 2")
    #expect(third.value(forHTTPHeaderField: "Authorization") == "Bearer 2")
    #expect(count.withLock { $0 } == 2)
  }

  @Test(arguments: ["configure", "acquire", "reject"])
  func providerStopErrorsSurviveCredentialBoundaries(stage: String) async throws {
    struct FailingProvider: TokenProvider {
      let identity = "application"
      let stop: Stop
      let stage: String
      func configure(_: SecurityBinding) throws -> TokenConfiguration {
        if stage == "configure" { throw stop }
        return .init(clientIdentity: "client")
      }
      func acquire(_: TokenRequest) throws -> TokenSet {
        if stage == "acquire" { throw stop }
        return .init(accessToken: "token")
      }
      func reject(_: TokenRequest, rejectedToken: String) throws -> Bool { throw stop }
    }
    let stop = Stop()
    let provider = FailingProvider(stop: stop, stage: stage)
    for managed in [false, true] {
      if stage == "reject" && managed { continue }
      let manager = try TokenManager(provider: provider)
      let selected: any TokenProvider = managed ? manager : provider
      do {
        let lease = try await selected.credentials(for: binding)
        _ = try await lease.invalidate()
        Issue.record("Expected the original stop error")
      }
      catch { #expect((error as? Stop) === stop) }
      await manager.close()
    }
  }
  @Test func consumingAdapterSuppliesItsOwnReplacementBody() async throws {
    let body = Data("adapter-owned-body".utf8)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { POST { request, response in
        #expect(request.body == body)
        response.send(status: .noContent)
      } }
    }
    let base = try await startTestServer(server)
    let consumed = Mutex(false)
    let adapter = Adapter(onRequest: { request in
      let stream = try #require(request.httpBodyStream)
      stream.open()
      defer { stream.close() }
      var replacement = Data()
      var buffer = [UInt8](repeating: 0, count: 16)
      while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count == 0 { break }
        guard count > 0 else { throw stream.streamError ?? Stop() }
        replacement.append(contentsOf: buffer.prefix(count))
      }
      consumed.withLock { $0 = true }
      var result = request
      result.httpBodyStream = InputStream(data: replacement)
      return result
    })
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: adapter, responseAdapter: adapter
    )
    defer { server.stop(); transport.close() }
    let spec = OperationSpec<StreamingBody>.streaming(
      method: .post, pathTemplate: "/value", body: StreamingBody(stream: { InputStream(data: body) }),
      contentTypes: [.octetStream]
    )
    try await transport.result(spec: spec)
    #expect(consumed.withLock { $0 })
  }

  @Test func lateResponseDoesNotInvalidateReplacementCredentials() async throws {
    let provider = Provider()
    let manager = try TokenManager(provider: provider)
    let adapter = AuthenticationAdapter(providers: ["identity": manager])
    let original = try URLRequest(url: URL(string: "https://api.example")!).withSecurity([binding])
    let first = try await adapter.adapt(request: original)
    let rejected = HTTPURLResponse(
      url: original.url!, statusCode: 401, httpVersion: nil,
      headerFields: ["WWW-Authenticate": "Bearer error=invalid_token"]
    )!
    _ = try await adapter.adapt(response: rejected, for: first)
    let replacement = try await adapter.adapt(request: original)
    _ = try await adapter.adapt(response: rejected, for: first)
    let current = try await adapter.adapt(request: original)
    #expect(
      current.value(forHTTPHeaderField: "Authorization") == replacement.value(forHTTPHeaderField: "Authorization")
    )
    #expect(await provider.refreshes == 1)
    await manager.close()
  }

  @Test(arguments: ["request", "response", "decoder"])
  func eventStreamThrowsOriginalStopError(stage: String) async throws {
    let stop = Stop()
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") { GET { _, response in
        response.send(status: .ok, headers: ["Content-Type": ["text/event-stream"]],
                      body: Data("data: value\n\n".utf8))
      } }
    }
    let base = try await startTestServer(server)
    let adapter = Adapter(onRequest: { request in
      if stage == "request" { throw stop }
      return request
    }, onResponse: { response, _ in
      if stage == "response" { throw stop }
      return response
    })
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: adapter, responseAdapter: adapter
    )
    defer { server.stop(); transport.close() }
    let stream: AsyncThrowingStream<String, any Error> = transport.eventStream(
      spec: OperationSpec<Empty>(method: .get, pathTemplate: "/events"),
      decoder: { _, _, _, _, _ in throw stop }
    )
    do {
      for try await _ in stream { Issue.record("Stopped operation must not yield events") }
      Issue.record("Expected the stream to throw")
    }
    catch { #expect((error as? Stop) === stop) }
  }

  private final class PendingBodyProtocol: URLProtocol, @unchecked Sendable {
    static let stopped = Mutex<AsyncStream<Void>.Continuation?>(nil)
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data("data: pending\n".utf8))
    }
    override func stopLoading() {
      Self.stopped.withLock { continuation in
        continuation?.yield(())
        continuation?.finish()
      }
    }
  }

  @Test(arguments: [false, true])
  func responseStopCancelsUnfinishedNativeBody(streaming: Bool) async throws {
    let stop = Stop()
    let (stopped, continuation) = AsyncStream<Void>.makeStream()
    PendingBodyProtocol.stopped.withLock { $0 = continuation }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PendingBodyProtocol.self]
    let session = URLSession(configuration: config)
    let transport = URLSessionTransport(
      baseURL: "https://api.example", session: session, eventSession: session,
      responseAdapter: Adapter(onResponse: { _, _ in throw stop })
    )
    defer {
      transport.close()
      PendingBodyProtocol.stopped.withLock { $0 = nil }
    }
    let spec = OperationSpec<Empty>(method: .get, pathTemplate: "/events")
    do {
      if streaming {
        let stream: AsyncThrowingStream<String, any Error> = transport.eventStream(
          spec: spec, decoder: { _, _, _, data, _ in data }
        )
        for try await _ in stream { Issue.record("No events should survive the response stop") }
      }
      else {
        try await transport.result(spec: spec)
      }
      Issue.record("Expected response stop")
    }
    catch { #expect((error as? Stop) === stop) }
    for await _ in stopped { break }
  }

  @Test func ordinaryAdapterErrorStillUsesNormalEventReconnectPolicy() async throws {
    struct Temporary: Error {}
    let attempts = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") { GET { _, response in
        response.send(status: .ok, headers: ["Content-Type": ["text/event-stream"]],
                      body: Data("data: recovered\n\n".utf8))
      } }
    }
    let base = try await startTestServer(server)
    let adapter = Adapter(onRequest: { request in
      if attempts.withLock({ $0 += 1; return $0 }) == 1 { throw Temporary() }
      return request
    })
    let transport = URLSessionTransport(
      baseURL: .init(format: base.absoluteString), requestAdapter: adapter, responseAdapter: adapter
    )
    defer { server.stop(); transport.close() }
    let stream: AsyncThrowingStream<String, any Error> = transport.eventStream(
      spec: OperationSpec<Empty>(method: .get, pathTemplate: "/events"),
      decoder: { _, _, _, data, _ in data }
    )
    for try await value in stream {
      #expect(value == "recovered")
      transport.close()
      break
    }
    #expect(attempts.withLock { $0 } == 2)
  }

}
