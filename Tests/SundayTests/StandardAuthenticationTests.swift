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
struct StandardAuthenticationTests {
  private let binding = SecurityBinding(
    scheme: "identity", provider: "identity", flow: .clientCredentials,
    transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
  )

  private final class Time: Sendable {
    let value = Mutex(Date(timeIntervalSince1970: 1000))
  }

  private actor Provider: RefreshingTokenProvider {
    nonisolated let identity = "standard-fixture"
    let now: Time
    var acquisitions = 0
    var refreshes = 0
    init(now: Time) { self.now = now }
    nonisolated func configure(_: SecurityBinding) -> TokenConfiguration { .init(clientIdentity: "client") }
    func acquire(_: TokenRequest) -> TokenSet {
      acquisitions += 1
      return .init(accessToken: "initial",
                   expiresAt: now.value.withLock { $0.addingTimeInterval(100) }, refreshToken: "r1")
    }
    func refresh(_: TokenRequest, refreshToken: String) -> TokenSet {
      refreshes += 1
      return .init(accessToken: "renewed-\(refreshes)",
                   expiresAt: now.value.withLock { $0.addingTimeInterval(100) }, refreshToken: "r2")
    }
  }

  @Test func generatedSettingsUseStandardPolicyAndExplicitManager() async throws {
    let now = Time()
    let provider = Provider(now: now)
    let manager = try TokenManager(provider: provider, expirySkew: 0, now: { now.value.withLock { $0 } })
    let sent = Mutex<[String]>([])
    let reject = Mutex(false)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { req, res in
        sent.withLock { $0.append(req.header(for: "Authorization") ?? "") }
        if reject.withLock({ $0 }) {
          res.send(status: .unauthenticated,
                   headers: ["WWW-Authenticate": ["Bearer error=invalid_token"]], body: Data())
        }
        else { res.send(status: .noContent) }
      } }
    }
    let base = try await startTestServer(server)
    let settings = try ClientSettings.resolve(baseURL: base, alternatives: ["read": [[binding]]],
      credentials: ["identity": ProviderCredentials(provider: manager)])
    let transport = URLSessionTransport(settings: settings)
    defer { transport.close(); server.stop() }
    #expect(settings.tokenProviders["identity"] as? TokenManager === manager)
    #expect(await provider.acquisitions == 0)
    // Same operation contract emitted by the generator; transport policy is supplied separately.
    let operation = OperationSpec<Empty>(method: .get, pathTemplate: "/value", security: settings.bindings["read"]!)
    _ = try await transport.transportResponse(spec: operation)
    _ = try await transport.transportResponse(spec: operation)
    now.value.withLock { $0 += 101 }
    _ = try await transport.transportResponse(spec: operation)
    #expect(await provider.acquisitions == 1)
    #expect(await provider.refreshes == 1)
    reject.withLock { $0 = true }
    await #expect(throws: TokenRejectedError.self) { try await transport.transportResponse(spec: operation) }
    #expect(sent.withLock { $0.count } == 4)
    reject.withLock { $0 = false }
    _ = try await transport.transportResponse(spec: operation)
    #expect(await provider.refreshes == 2)
    await manager.close()
  }

  private final class Custom: RequestAdapter, ResponseAdapter {
    let calls = Mutex(0)
    func adapt(request: URLRequest) async throws -> URLRequest {
      calls.withLock { $0 += 1 }
      var request = request
      request.setValue("Custom credential", forHTTPHeaderField: "Authorization")
      return request
    }
    func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse { response }
  }

  @Test func sameOperationSupportsCustomAndUnauthenticatedTransports() async throws {
    let sent = Mutex<[String]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/value") { GET { req, res in
        sent.withLock { $0.append(req.header(for: "Authorization") ?? "") }
        res.send(status: .noContent)
      } }
    }
    let base = try await startTestServer(server)
    let custom = Custom()
    let direct = URLSessionTransport(baseURL: .init(format: base.absoluteString),
                                    requestAdapter: custom, responseAdapter: custom)
    let plain = URLSessionTransport(baseURL: .init(format: base.absoluteString))
    let standard = StandardAuthenticationAdapter(providers: [:])
    let missing = URLSessionTransport(baseURL: .init(format: base.absoluteString),
                                     requestAdapter: standard, responseAdapter: standard)
    defer { direct.close(); plain.close(); missing.close(); server.stop() }
    let operation = OperationSpec<Empty>(method: .get, pathTemplate: "/value", security: [binding])
    _ = try await direct.transportResponse(spec: operation)
    _ = try await plain.transportResponse(spec: operation)
    await #expect { try await missing.transportResponse(spec: operation) } throws: { error in
      error is any RequestCancellationError
    }
    #expect(custom.calls.withLock { $0 } == 1)
    #expect(sent.withLock { $0 } == ["Custom credential", ""])
  }
}
