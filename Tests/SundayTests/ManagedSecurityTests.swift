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

@Suite(.serialized)
struct ManagedSecurityTests {
  private let binding = SecurityBinding(
    scheme: "identity", provider: "identity", flow: .clientCredentials, profile: "external",
    transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
  )

  private actor Provider: RefreshingTokenProvider {
    nonisolated let identity = "application"
    var acquired = 0
    var refreshed = 0
    nonisolated func configure(_ binding: SecurityBinding) -> TokenConfiguration {
      TokenConfiguration(clientIdentity: "client")
    }

    func acquire(_ request: TokenRequest) -> TokenSet {
      acquired += 1
      return TokenSet(accessToken: "first-\(acquired)", refreshToken: "refresh")
    }

    func refresh(_ request: TokenRequest, refreshToken: String) -> TokenSet {
      refreshed += 1
      return TokenSet(accessToken: "renewed-\(refreshed)", refreshToken: "rotated")
    }
  }

  private func transport(_ server: RoutingHTTPServer, manager: TokenManager?) async throws -> URLSessionTransport {
    let base = try await startTestServer(server)
    return URLSessionTransport(baseURL: .init(format: base.absoluteString), tokenManager: manager)
  }

  @Test func nativeRequestReuseRechecksCredentialsAndRecoversOnce() async throws {
    let values = Mutex<[String]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") {
        GET { req, res in
          let first = values.withLock { $0.append(req.header(for: "Authorization") ?? ""); return $0.count == 1 }
          if first {
            res.send(status: .unauthenticated,
                     headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]], body: Data())
          }
          else { res.send(status: .noContent) }
        }
      }
    }
    let provider = Provider()
    let manager = try TokenManager(providers: ["identity": provider])
    let transport = try await transport(server, manager: manager)
    defer { server.stop(); transport.close() }
    let request = try await transport.transportRequest(spec: OperationSpec<Empty>(
      method: .get, pathTemplate: "/value", security: [binding]
    ))
    #expect(try await transport.transportResponse(request: request).statusCode == 204)
    try await manager.invalidate(manager.credentials(for: binding))
    #expect(try await transport.transportResponse(request: request).statusCode == 204)
    #expect(values.withLock { $0 } == ["Bearer first-1", "Bearer renewed-1", "Bearer renewed-2"])
    #expect(await provider.acquired == 1)
    #expect(await provider.refreshed == 2)
    await manager.close()
  }

  @Test(arguments: [HTTP.Method.post, .get])
  func unsafeOrRepeatedChallengesCannotKeepReplaying(method: HTTP.Method) async throws {
    let count = Mutex(0)
    let handler: @Sendable (any HTTPRequest, any HTTPResponse) -> Void = { _, res in
      count.withLock { $0 += 1 }
      res.send(status: .unauthenticated,
                     headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]], body: Data())
    }
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET(handler); POST(handler) }
    }
    let provider = Provider()
    let manager = try TokenManager(providers: ["identity": provider])
    let transport = try await transport(server, manager: manager)
    defer { server.stop(); transport.close() }
    await #expect(throws: SundayError.self) {
      try await transport.transportResponse(spec: OperationSpec<Empty>(
        method: method, pathTemplate: "/value", security: [binding]
      ))
    }
    #expect(count.withLock { $0 } == (method == .get ? 2 : 1))
    #expect(await provider.refreshed == (method == .get ? 1 : 0))
    await manager.close()
  }

  @Test(arguments: [
    "Bearer error=invalid_token",
    "Bearer realm=api, Basic, error=invalid_token",
    "Bearer error=INVALID_TOKEN",
  ])
  func forbiddenAndUnrecognizedChallengesDoNotRecover(challenge: String) async throws {
    let count = Mutex(0)
    let status: HTTP.Response.Status = challenge == "Bearer error=invalid_token" ? .forbidden : .unauthenticated
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") {
        GET { _, res in
          count.withLock { $0 += 1 }
          res.send(status: status, headers: ["WWW-Authenticate": [challenge]], body: Data())
        }
      }
    }
    let provider = Provider()
    let manager = try TokenManager(providers: ["identity": provider])
    let transport = try await transport(server, manager: manager)
    defer { server.stop(); transport.close() }
    await #expect(throws: SundayError.self) {
      try await transport.transportResponse(spec: OperationSpec<Empty>(
        method: .get,
        pathTemplate: "/value",
        security: [binding]
      ))
    }
    #expect(count.withLock { $0 } == 1)
    #expect(await provider.refreshed == 0)
    await manager.close()
  }

  @Test func ANDCredentialsKeepBodyAndEncodedQueryAndRedactResponseURL() async throws {
    let observed = Mutex(false)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") {
        POST { req, res in
          #expect(req.header(for: "Authorization") == "Bearer first-1")
          #expect(req.header(for: "Cookie") == "session=first-3")
          #expect(String(data: req.body ?? Data(), encoding: .utf8) == #"{"value":"same"}"#)
          observed.withLock { $0 = true }
          res.send(status: .noContent)
        }
      }
    }
    let manager = try TokenManager(providers: ["identity": Provider()])
    let transport = try await transport(server, manager: manager)
    defer { server.stop(); transport.close() }
    let key = SecurityBinding(
      scheme: "key",
      provider: "identity",
      flow: .static,
      transport: .init(location: .query, name: "key")
    )
    let cookie = SecurityBinding(
      scheme: "cookie",
      provider: "identity",
      flow: .external,
      transport: .init(location: .cookie, name: "session")
    )
    let request = try await transport.transportRequest(spec: OperationSpec(
      method: .post, pathTemplate: "/value", queryParameters: ["unchanged": "a+b"], body: ["value": "same"],
      contentTypes: [.json], security: [binding, key, cookie]
    ))
    #expect(request.url?.absoluteString.contains("unchanged=a%2Bb") == true)
    #expect(request.url?.absoluteString.contains("key=first-2") == true)
    let response = try await transport.transportResponse(request: request)
    #expect(observed.withLock { $0 })
    #expect(response.url?.absoluteString.contains("first-") == false)
    #expect(response.url?.absoluteString.contains("unchanged=a%2Bb") == true)
    await manager.close()
  }

  @Test func redirectsAreNotFollowedAndMissingProvidersOrConflictsFailBeforeSending() async throws {
    let count = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") {
        GET { _, res in
          count.withLock { $0 += 1 }
          res.send(status: .temporaryRedirect, headers: ["Location": ["/other"]], body: Data())
        }
      }
      Path("/other") { GET { _, res in count.withLock { $0 += 1 }; res.send(status: .noContent) } }
    }
    let manager = try TokenManager(providers: ["identity": Provider()])
    let transport = try await transport(server, manager: manager)
    defer { server.stop(); transport.close() }
    #expect(try await transport.transportResponse(spec: OperationSpec<Empty>(
      method: .get, pathTemplate: "/value", security: [binding]
    )).statusCode == 307)
    await #expect(throws: TokenProviderError.self) {
      try await transport.transportRequest(spec: OperationSpec<Empty>(
        method: .get, pathTemplate: "/value", headers: ["Authorization": "existing"], security: [binding]
      ))
    }
    let missing = URLSessionTransport(baseURL: transport.baseURL)
    defer { missing.close() }
    await #expect(throws: TokenProviderError.self) {
      try await missing.transportRequest(spec: OperationSpec<Empty>(
        method: .get,
        pathTemplate: "/value",
        security: [binding]
      ))
    }
    #expect(count.withLock { $0 } == 1)
    await manager.close()
  }

  @Test func eventConnectionsShareOneRecoveryBudgetAcrossReconnects() async throws {
    let count = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") {
        GET { _, res in
          let current = count.withLock { $0 += 1; return $0 }
          if current == 2 {
            res.send(status: .ok, headers: ["Content-Type": ["text/event-stream"]], body: Data("data: value\n\n".utf8))
          }
          else { res.send(
            status: .unauthenticated,
            headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]],
            body: Data()
          ) }
        }
      }
    }
    let provider = Provider()
    let manager = try TokenManager(providers: ["identity": provider])
    let transport = try await transport(server, manager: manager)
    defer { server.stop(); transport.close() }
    let spec = OperationSpec<Empty>(method: .get, pathTemplate: "/events", security: [binding])
    let source = transport.eventSource(spec: spec)
    let (closed, continuation) = AsyncStream<Void>.makeStream()
    await source.setOnStateError { error, state in
      if error != nil, state == .closed { continuation.yield(()); continuation.finish() }
    }
    await source.connect()
    for await _ in closed {
      break
    }
    await source.close()
    #expect(count.withLock { $0 } == 3)
    #expect(await provider.refreshed == 1)
    await manager.close()
  }
  @Test func temporaryCredentialFailureReconnectsEvents() async throws {
    actor IntermittentProvider: TokenProvider {
      nonisolated let identity = "application"
      var attempts = 0
      nonisolated func configure(_ binding: SecurityBinding) -> TokenConfiguration {
        TokenConfiguration(clientIdentity: "client")
      }
      func acquire(_ request: TokenRequest) throws -> TokenSet {
        attempts += 1
        if attempts == 1 { throw TokenProviderError(reason: .temporary) }
        return TokenSet(accessToken: "recovered")
      }
    }
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") {
        GET { _, res in
          res.send(
            status: .ok, headers: ["Content-Type": ["text/event-stream"]], body: Data("data: recovered\n\n".utf8)
          )
        }
      }
    }
    let provider = IntermittentProvider()
    let manager = try TokenManager(providers: ["identity": provider])
    let transport = try await transport(server, manager: manager)
    defer { server.stop(); transport.close() }
    let source = transport.eventSource(spec: OperationSpec<Empty>(
      method: .get, pathTemplate: "/events", security: [binding]
    ))
    let (messages, continuation) = AsyncStream<String>.makeStream()
    await source.setOnMessage { _, _, value in
      if let value { continuation.yield(value); continuation.finish() }
    }
    await source.connect()
    for await value in messages { #expect(value == "recovered"); break }
    await source.close()
    #expect(await provider.attempts == 2)
    await manager.close()
  }

}
