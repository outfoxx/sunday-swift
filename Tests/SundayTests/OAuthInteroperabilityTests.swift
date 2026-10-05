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

#if os(macOS)
import Foundation
import Sunday
import Testing

@Suite(.serialized)
struct OAuthInteroperabilityTests {
  @Test func managedAcquisitionAndRotation() async throws {
    let infrastructure = try ManagedOAuthProvider()
    do {
      try await infrastructure.start()
      for authentication in [URLSessionOAuthTokenProvider.Authentication.none, .clientSecretBasic, .clientSecretPost] {
        try await scenario(infrastructure, authentication: authentication)
      }
      await infrastructure.close()
    }
    catch {
      await infrastructure.close()
      throw error
    }
  }

  private func scenario(
    _ infrastructure: ManagedOAuthProvider, authentication: URLSessionOAuthTokenProvider.Authentication
  ) async throws {
    let clientID = authentication == .none ? "public" : (authentication == .clientSecretBasic ? "basic" : "post")
    let issuer = await infrastructure.issuer
    if infrastructure.mode == "replay" {
      try await replay(infrastructure, clientID: clientID, authentication: authentication)
    }
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "interop", clientID: clientID, clientSecret: authentication == .none ? nil : "synthetic-secret",
      authentication: authentication, issuer: issuer,
      authorize: { _ in
        let grant = try await infrastructure.authorize(clientID: clientID)
        return AuthorizationGrant(code: grant.code, redirectURI: infrastructure.callback, codeVerifier: grant.verifier)
      }
    ))
    let request = TokenRequest(binding: SecurityBinding(
      scheme: "identity", provider: "identity", flow: .authorizationCode,
      endpoints: .init(discoveryURL: issuer + "/.well-known/openid-configuration"),
      transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
    ), clientIdentity: clientID)
    let acquired = try await provider.acquire(request)
    let refresh = try #require(acquired.refreshToken)
    let rotated = try await provider.refresh(request, refreshToken: refresh)
    #expect(rotated.refreshToken != nil && rotated.refreshToken != refresh)
    await #expect(throws: AuthorizationRequiredError.self) {
      try await provider.refresh(request, refreshToken: refresh)
    }
  }

  private func admin(_ base: String, _ path: String, method: String, body: [String: Any]? = nil) async throws {
    var request = URLRequest(url: URL(string: base + path)!)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (_, response) = try await URLSession.shared.data(for: request)
    let status = try #require((response as? HTTPURLResponse)?.statusCode)
    #expect((200 ... 299).contains(status))
  }

  private func replay(
    _ infrastructure: ManagedOAuthProvider, clientID: String,
    authentication: URLSessionOAuthTokenProvider.Authentication
  ) async throws {
    let base = await infrastructure.base
    let issuer = await infrastructure.issuer
    let callback = infrastructure.callback
    let realmPath = URL(string: issuer)!.path
    let token = realmPath + "/protocol/openid-connect/token"
    try await admin(base, "/__admin/mappings", method: "DELETE")
    try await admin(base, "/__admin/scenarios/reset", method: "POST")
    try await admin(base, "/__admin/mappings", method: "POST", body: [
      "request": ["method": "GET", "urlPath": realmPath + "/.well-known/openid-configuration"],
      "response": ["status": 200, "jsonBody": ["issuer": issuer, "token_endpoint": base + token,
                                              "authorization_endpoint": issuer + "/protocol/openid-connect/auth",
                                              "token_endpoint_auth_methods_supported": [
                                                "client_secret_basic", "client_secret_post",
                                              ],
      ],
      ],
    ])
    for (index, grant) in ["authorization_code", "refresh_token"].enumerated() {
      var form = ["grant_type": ["equalTo": grant]]
      if index == 0 {
        form["code"] = ["equalTo": "synthetic-code"]
        form["code_verifier"] = ["equalTo": String(repeating: "v", count: 64)]
        form["redirect_uri"] = ["equalTo": callback]
      }
      else { form["refresh_token"] = ["equalTo": "synthetic-refresh-1"] }
      var headers: [String: Any] = [:]
      if authentication == .clientSecretBasic {
        let basic = Data((clientID + ":synthetic-secret").utf8).base64EncodedString()
        headers["Authorization"] = ["equalTo": "Basic " + basic]
      }
      else {
        form["client_id"] = ["equalTo": clientID]
        if authentication == .clientSecretPost { form["client_secret"] = ["equalTo": "synthetic-secret"] }
      }
      try await admin(base, "/__admin/mappings", method: "POST", body: [
        "scenarioName": "rotation", "requiredScenarioState": index == 0 ? "Started" : "acquired",
        "newScenarioState": index == 0 ? "acquired" : "rotated",
        "request": ["method": "POST", "urlPath": token, "formParameters": form, "headers": headers],
        "response": ["status": 200, "jsonBody": ["access_token": "synthetic-access-\(index)", "token_type": "Bearer",
                                                "expires_in": 60, "refresh_token": "synthetic-refresh-\(index + 1)",
      ],
      ],
      ])
    }
    try await admin(base, "/__admin/mappings", method: "POST", body: [
      "priority": 10, "request": ["method": "POST", "urlPath": token],
      "response": ["status": 400, "jsonBody": ["error": "invalid_grant"]],
    ])
  }

  @Test func infrastructureSelection() throws {
    for value in [nil, "", "0", "false", "FALSE"] as [String?] {
      #expect(try ManagedOAuthProvider.selectBackend(mode: "live", ci: value, macOS: true) == "keycloak-container")
    }
    for value in ["1", "true", "github"] {
      #expect(try ManagedOAuthProvider.selectBackend(mode: "live", ci: value, macOS: true) == "keycloak-java")
      #expect(try ManagedOAuthProvider.selectBackend(mode: "replay", ci: value, macOS: true) == "wiremock-java")
    }
    #expect(throws: ManagedOAuthProvider.Failure.self) {
      try ManagedOAuthProvider.selectBackend(mode: "automatic", ci: "true", macOS: true)
    }
  }
}
#endif
