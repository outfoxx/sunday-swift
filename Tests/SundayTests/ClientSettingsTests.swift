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
import Synchronization
import Testing

struct ClientSettingsTests {
  private let binding = SecurityBinding(
    scheme: "identity", provider: "identity", flow: .static,
    transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
  )

  @Test func staticCredentialsRemainPrivate() async throws {
    let settings = try ClientSettings(
      baseURL: URL(string: "https://api.example")!,
      bindings: ["list": [binding]],
      credentials: ["identity": BearerCredentials(token: "private-token")]
    )
    let manager = try #require(settings.tokenManager)
    let lease = try await manager.credentials(for: binding)
    #expect(lease.tokens.accessToken == "private-token")
    #expect(!String(reflecting: settings).contains("private-token"))
    #expect(!String(reflecting: BearerCredentials(token: "private-token")).contains("private-token"))
  }

  @Test func configurationsIsolateTokenManagers() async throws {
    let first = try ClientSettings(
      baseURL: URL(string: "https://one.example")!,
      bindings: ["list": [binding]],
      credentials: ["identity": BearerCredentials(token: "one")]
    )
    let second = try ClientSettings(
      baseURL: URL(string: "https://two.example")!,
      bindings: ["list": [binding]],
      credentials: ["identity": BearerCredentials(token: "two")]
    )
    let firstManager = try #require(first.tokenManager)
    let secondManager = try #require(second.tokenManager)
    #expect(try await firstManager.credentials(for: binding).tokens.accessToken == "one")
    #expect(try await secondManager.credentials(for: binding).tokens.accessToken == "two")
  }

  @Test func incompatibleCredentialsFailBeforeTransportConstruction() {
    #expect(throws: TokenProviderError.self) {
      try ClientSettings(baseURL: URL(string: "https://api.example")!, bindings: ["list": [binding]])
    }
    #expect(throws: TokenProviderError.self) {
      try ClientSettings(
        baseURL: URL(string: "https://api.example")!,
        bindings: ["list": [binding]],
        credentials: ["identity": ApiKeyCredentials(key: "secret")]
      )
    }
  }

  @Test func configuredProviderIsBuiltWithoutAcquisition() throws {
    let oauth = SecurityBinding(
      scheme: "identity",
      provider: "identity",
      flow: .clientCredentials,
      transport: binding.transport
    )
    let calls = Mutex(0)
    let credential = OAuthCredentials.clientCredentials(
      .init(identity: "application", clientID: "client", clientSecret: "secret", authentication: .clientSecretBasic),
      providerFactory: { config in
        calls.withLock { $0 += 1 }
        return try URLSessionOAuthTokenProvider(configuration: config)
      }
    )
    let settings = try ClientSettings.resolve(
      baseURL: URL(string: "https://api.example")!,
      alternatives: ["list": [[oauth]], "read": [[oauth]]],
      credentials: ["identity": credential]
    )
    #expect(settings.tokenManager != nil)
    #expect(calls.withLock { $0 } == 1)
  }

  @Test func completeAlternativesAndPublicOverrides() throws {
    let key = SecurityBinding(
      scheme: "key",
      provider: "key",
      flow: .static,
      transport: .init(location: .query, name: "key")
    )
    let credentials: [String: any Credentials] = [
      "identity": BearerCredentials(token: "one"),
      "key": ApiKeyCredentials(key: "two"),
    ]
    let alternatives = ["list": [[binding, key], [binding]], "public": [[]]]
    let endpoint = URL(string: "https://api.example")!
    #expect(throws: TokenProviderError.self) { try ClientSettings.resolve(
      baseURL: endpoint,
      alternatives: alternatives,
      credentials: credentials
    ) }
    let settings = try ClientSettings.resolve(
      baseURL: endpoint,
      alternatives: alternatives,
      credentials: credentials,
      selection: ["list": ["identity", "key"]]
    )
    #expect(settings.bindings["list"]?.map(\.scheme) == ["identity", "key"])
    #expect(settings.bindings["public"]?.isEmpty == true)
  }

  @Test func relativeEndpointsAndSecurityTemplates() throws {
    let endpoint = try ClientSettings.serverURL(
      template: "../{version}",
      variables: ["version": "v2"],
      documentBaseURL: URL(string: "https://api.example/spec/openapi.yaml")
    )
    #expect(endpoint.absoluteString == "https://api.example/v2")
    let relative = binding.overridingEndpoints(.init(tokenURL: "oauth/token"))
    let settings = try ClientSettings(
      baseURL: endpoint,
      bindings: ["list": [relative]],
      credentials: ["identity": BearerCredentials(token: "secret")]
    )
    #expect(settings.bindings["list"]?.first?.endpoints.tokenURL == "https://api.example/oauth/token")
    #expect(throws: TokenProviderError.self) { try ClientSettings.serverURL(template: "/v2", variables: [:]) }
  }

}
