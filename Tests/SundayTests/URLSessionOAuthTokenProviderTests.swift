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
import Sunday
@testable import SundayServer
import Synchronization
import Testing

@Suite(.serialized)
struct URLSessionOAuthTokenProviderTests {
  private func request(
    _ url: URL,
    flow: SecurityBinding.Flow = .clientCredentials,
    scopes: Set<String> = ["read"],
    discovery: String? = nil
  ) -> TokenRequest {
    TokenRequest(binding: SecurityBinding(
      scheme: "identity", provider: "application", flow: flow, profile: "external", scopes: scopes,
      endpoints: .init(discoveryURL: discovery, tokenURL: url.absoluteString),
      transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
    ), clientIdentity: "client:name", grantIdentity: "session")
  }

  private func start(_ server: RoutingHTTPServer) async throws -> URL {
    try await startTestServer(server)
  }

  private func form(_ body: Data?) -> [String: String] {
    let raw = String(data: body ?? Data(), encoding: .utf8) ?? ""
    return Dictionary(uniqueKeysWithValues: raw.split(separator: "&").map { entry in
      let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let decode: (Substring) -> String = {
        $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
      }
      return (decode(parts[0]), parts.count > 1 ? decode(parts[1]) : "")
    })
  }

  @Test(arguments: [URLSessionOAuthTokenProvider.Authentication.clientSecretBasic, .clientSecretPost])
  func nativeClientCredentialsAndRotation(authentication: URLSessionOAuthTokenProvider.Authentication) async throws {
    let captured = Mutex<[[String: String]]>([])
    let authorization = Mutex<[String]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/token") {
        POST { req, res in
          captured.withLock { $0.append(form(req.body)) }
          authorization.withLock { $0.append(req.header(for: "Authorization") ?? "") }
          #expect(req.header(for: "Cookie") == nil)
          res.send(status: .ok, headers: ["Content-Type": ["application/json"]], body: Data(
            #"{"access_token":"token","token_type":"Bearer","expires_in":120,"refresh_token":"rotated","scope":"read"}"#
              .utf8
          ))
        }
      }
    }
    let url = try await start(server).appendingPathComponent("token")
    defer { server.stop() }
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.httpAdditionalHeaders = ["Authorization": "ambient", "Cookie": "session=ambient"]
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "application", clientID: "client:name", clientSecret: "secret+ value", authentication: authentication
    ), sessionConfiguration: sessionConfiguration, now: { Date(timeIntervalSince1970: 1000) })
    let first = try await provider.acquire(request(url))
    let renewed = try await provider.refresh(request(url), refreshToken: "previous")
    #expect(first.expiresAt == Date(timeIntervalSince1970: 1120))
    #expect(renewed.refreshToken == "rotated")
    let values = captured.withLock { $0 }
    #expect(values[0]["grant_type"] == "client_credentials")
    #expect(values[1]["grant_type"] == "refresh_token")
    #expect(values[1]["refresh_token"] == "previous")
    if authentication == .clientSecretBasic {
      let expected = "Basic " + Data("client%3Aname:secret%2B+value".utf8).base64EncodedString()
      #expect(authorization.withLock { $0 } == [expected, expected])
      #expect(values[0]["client_secret"] == nil)
    }
    else {
      #expect(authorization.withLock { $0 } == ["", ""])
      #expect(values[0]["client_id"] == "client:name")
      #expect(values[0]["client_secret"] == "secret+ value")
    }
  }

  @Test func applicationPKCECodesAreOneUseAcrossCacheKeys() async throws {
    let captured = Mutex<[[String: String]]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/token") {
        POST { req, res in
          let values = form(req.body)
          captured.withLock { $0.append(values) }
          if values["grant_type"] == "refresh_token" {
            res.send(status: .badRequest, text: #"{"error":"invalid_grant"}"#)
          }
          else {
            res.send(status: .ok, text: #"{"access_token":"token","token_type":"Bearer","refresh_token":"refresh"}"#)
          }
        }
      }
    }
    let url = try await start(server).appendingPathComponent("token")
    defer { server.stop() }
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "application", clientID: "public", grantIdentity: "fresh-session",
      authorize: { _ in AuthorizationGrant(
        code: "one-use",
        redirectURI: "app://callback",
        codeVerifier: String(repeating: "v", count: 43)
      ) }
    ))
    _ = try await provider.acquire(request(url, flow: .authorizationCode))
    await #expect(throws: AuthorizationRequiredError.self) {
      try await provider.acquire(request(url, flow: .authorizationCode, scopes: ["write"]))
    }
    await #expect(throws: AuthorizationRequiredError.self) {
      try await provider.refresh(request(url, flow: .authorizationCode), refreshToken: "refresh")
    }
    #expect(captured.withLock { $0.count } == 2)
    #expect(captured.withLock { $0[0]["code_verifier"] } == String(repeating: "v", count: 43))
    #expect(captured.withLock { $0[0]["redirect_uri"] } == "app://callback")
    #expect(captured.withLock { $0[1]["code"] } == nil)
  }

  @Test(arguments: [
    Optional(#"["private_key_jwt","client_secret_basic","client_secret_post","tls_client_auth","client_secret_jwt"]"#),
    #"["none"]"#,
    "[]",
    nil,
  ])
  func publicDiscoverySupportsExchangeAndRefresh(authenticationMethods: String?) async throws {
    let captured = Mutex<[[String: String]]>([])
    let tokenEndpoint = Mutex("")
    let authorizations = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/discovery") {
        GET { _, res in
          let methods = authenticationMethods.map { ",\"token_endpoint_auth_methods_supported\":\($0)" } ?? ""
          res.send(
            status: .ok,
            text:
            "{\"issuer\":\"https://trusted.example\"," +
              "\"authorization_endpoint\":\"https://trusted.example/authorize\"," +
              "\"token_endpoint\":\"\(tokenEndpoint.withLock { $0 })\"\(methods)}"
          )
        }
      }
      Path("/token") {
        POST { req, res in
          captured.withLock { $0.append(form(req.body)) }
          #expect(req.header(for: "Authorization") == nil)
          #expect(req.header(for: "Cookie") == nil)
          res.send(
            status: .ok,
            text:
            #"{"access_token":"token","token_type":"Bearer","refresh_token":"refresh","scope":"openid"}"#
          )
        }
      }
    }
    let base = try await start(server)
    defer { server.stop() }
    tokenEndpoint.withLock { $0 = base.appendingPathComponent("token").absoluteString }
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.httpAdditionalHeaders = ["Authorization": "ambient", "Cookie": "session=ambient"]
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "application", clientID: "public", clientSecret: "unused-secret", authentication: .none,
      grantIdentity: "session", issuer: "https://trusted.example",
      authorize: { _ in
        authorizations.withLock { $0 += 1 }
        return AuthorizationGrant(
          code: "fresh-code", redirectURI: "http://127.0.0.1/callback", codeVerifier: String(repeating: "v", count: 43)
        )
      }
    ), sessionConfiguration: sessionConfiguration)
    let manager = try TokenManager(providers: ["application": provider])
    let binding = SecurityBinding(
      scheme: "identity", provider: "application", flow: .authorizationCode, profile: "external", scopes: ["openid"],
      endpoints: .init(discoveryURL: base.appendingPathComponent("discovery").absoluteString),
      transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
    )
    let first = try await manager.credentials(for: binding)
    try await manager.invalidate(first)
    let renewed = try await manager.credentials(for: binding)
    await manager.close()
    #expect(first.tokens.accessToken == "token")
    #expect(renewed.tokens.refreshToken == "refresh")
    #expect(authorizations.withLock { $0 } == 1)
    #expect(captured.withLock { $0 } == [
      [
        "grant_type": "authorization_code", "client_id": "public", "code": "fresh-code",
        "redirect_uri": "http://127.0.0.1/callback", "code_verifier": String(repeating: "v", count: 43),
        "scope": "openid",
      ],
      ["grant_type": "refresh_token", "client_id": "public", "refresh_token": "refresh", "scope": "openid"],
    ])
  }

  @Test(arguments: [
    (
      URLSessionOAuthTokenProvider.Authentication.none,
      Optional("https://wrong.example"),
      Optional(#"["none"]"#),
      false
    ),
    (.none, "https://wrong.example", nil, false),
    (.none, nil, nil, false),
    (.clientSecretBasic, "https://trusted.example", #"["client_secret_post"]"#, false),
    (.clientSecretPost, "https://trusted.example", #"["client_secret_basic"]"#, false),
    (.clientSecretPost, "https://trusted.example", nil, false),
    (.clientSecretBasic, "https://trusted.example", nil, true),
  ])
  func discoveryPreservesIssuerAndConfidentialAuthenticationChecks(
    authentication: URLSessionOAuthTokenProvider.Authentication, issuer: String?,
    authenticationMethods: String?, accepted: Bool
  ) async throws {
    let exchanges = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/discovery") {
        GET { _, res in
          let methods = authenticationMethods.map { ",\"token_endpoint_auth_methods_supported\":\($0)" } ?? ""
          res.send(
            status: .ok,
            text:
            "{\"issuer\":\"https://trusted.example\"," +
              "\"authorization_endpoint\":\"https://trusted.example/authorize\"," +
              "\"token_endpoint\":\"https://internal.example/token\"\(methods)}"
          )
        }
      }
      Path("/token") {
        POST { _, res in
          exchanges.withLock { $0 += 1 }
          res.send(status: .ok, text: #"{"access_token":"token","token_type":"Bearer"}"#)
        }
      }
    }
    let base = try await start(server)
    defer { server.stop() }
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "application", clientID: "client", clientSecret: "secret", authentication: authentication,
      grantIdentity: "session", issuer: issuer,
      authorize: { _ in AuthorizationGrant(
        code: "fresh-code", redirectURI: "app://callback", codeVerifier: String(repeating: "v", count: 43)
      ) }
    ))
    let selected = request(
      base.appendingPathComponent("token"),
      flow: authentication == .none ? .authorizationCode : .clientCredentials,
      discovery: base.appendingPathComponent("discovery").absoluteString
    )
    if accepted {
      _ = try await provider.acquire(selected)
      _ = try await provider.refresh(selected, refreshToken: "refresh")
    }
    else {
      await #expect(throws: TokenProviderError.self) { try await provider.acquire(selected) }
      await #expect(throws: TokenProviderError.self) { try await provider.refresh(selected, refreshToken: "refresh") }
    }
    #expect(exchanges.withLock { $0 } == (accepted ? 2 : 0))
  }

  @Test func discoveryRequiresIndependentIssuerAndKeepsEndpointOverride() async throws {
    let requests = Mutex<[String]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/discovery") {
        GET { _, res in
          requests.withLock { $0.append("discovery") }
          res.send(
            status: .ok,
            text:
            #"""
              {"issuer":"https://trusted.example","token_endpoint":"https://internal.example/token",
               "token_endpoint_auth_methods_supported":["client_secret_post"]}
              """#
          )
        }
      }
      Path("/override") {
        POST { _, res in
          requests.withLock { $0.append("override") }
          res.send(status: .ok, text: #"{"access_token":"token","token_type":"Bearer"}"#)
        }
      }
    }
    let base = try await start(server)
    defer { server.stop() }
    let selected = request(
      base.appendingPathComponent("override"),
      discovery: base.appendingPathComponent("discovery").absoluteString
    )
    for issuer in ["https://trusted.example", "https://wrong.example"] {
      let provider = try URLSessionOAuthTokenProvider(configuration: .init(
        identity: "application", clientID: "client", clientSecret: "secret", authentication: .clientSecretPost,
        issuer: issuer
      ))
      if issuer == "https://trusted.example" {
        _ = try await provider.acquire(selected)
        _ = try await provider.refresh(selected, refreshToken: "refresh")
      }
      else { await #expect(throws: TokenProviderError.self) { try await provider.acquire(selected) } }
    }
    #expect(requests.withLock { $0 } == ["discovery", "override", "discovery", "override", "discovery"])
  }

  @Test(arguments: [
    #"{"access_token":"","token_type":"Bearer"}"#,
    #"{"access_token":"token","token_type":"Basic"}"#,
    #"{"access_token":"token","token_type":"Bearer","expires_in":0}"#,
    #"{"access_token":"token","token_type":"Bearer","expires_in":true}"#,
    #"{"access_token":"token","token_type":"Bearer","refresh_token":""}"#,
    #"{"access_token":"token","token_type":"Bearer","scope":"other"}"#,
  ])
  func invalidTokenResponsesFailSafely(body: String) async throws {
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/token") { POST { _, res in res.send(status: .ok, text: body) } }
    }
    let base = try await start(server)
    defer { server.stop() }
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "application", clientID: "client", clientSecret: "secret", authentication: .clientSecretPost
    ))
    await #expect(throws: TokenProviderError.self) {
      try await provider.acquire(request(base.appendingPathComponent("token")))
    }
  }

  @Test func tokenEndpointRedirectsAndInsecureRemoteEndpointsAreRejected() async throws {
    let count = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/token") {
        POST { _, res in
          count.withLock { $0 += 1 }
          res.send(status: .temporaryRedirect, headers: ["Location": ["/other"]], body: Data())
        }
      }
      Path("/other") { POST { _, res in count.withLock { $0 += 1 }; res.send(status: .noContent) } }
    }
    let base = try await start(server)
    defer { server.stop() }
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "application", clientID: "client", clientSecret: "secret", authentication: .clientSecretPost
    ))
    await #expect(throws: TokenProviderError.self) {
      try await provider.acquire(request(base.appendingPathComponent("token")))
    }
    #expect(count.withLock { $0 } == 1)
    for raw in [
      "http://identity.example/token",
      "https://user:secret@identity.example/token",
      "https://identity.example/token#fragment",
    ] {
      let url = try #require(URL(string: raw))
      await #expect(throws: TokenProviderError.self) { try await provider.acquire(request(url)) }
    }
  }

  @Test func cancellationReachesNativeTokenExchange() async throws {
    let (events, continuation) = AsyncStream<Void>.makeStream()
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/token") { POST { _, _ in continuation.yield(()) } }
    }
    let base = try await start(server)
    defer { server.stop(); continuation.finish() }
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "application", clientID: "client", clientSecret: "secret", authentication: .clientSecretPost
    ))
    let call = Task { try await provider.acquire(request(base.appendingPathComponent("token"))) }
    for await _ in events {
      break
    }
    call.cancel()
    await #expect(throws: CancellationError.self) { try await call.value }
  }
  @Test func providerErrorsClassifyOutagesAndRejectedGrants() async throws {
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/outage") { POST { _, res in res.send(status: .internalServerError, text: "SECRET outage") } }
      Path("/invalid") { POST { _, res in res.send(status: .badRequest, text: #"{"error":"invalid_grant"}"#) } }
      Path("/terminal") { POST { _, res in res.send(status: .badRequest, text: #"{"error":"invalid_client"}"#) } }
    }
    let base = try await start(server)
    defer { server.stop() }
    let provider = try URLSessionOAuthTokenProvider(configuration: .init(
      identity: "app", clientID: "client", clientSecret: "secret", authentication: .clientSecretPost
    ))
    let cases: [(String, TokenProviderError.Reason)] = [
      ("outage", .temporary), ("invalid", .invalidGrant), ("terminal", .unavailable),
    ]
    for (path, reason) in cases {
      do {
        _ = try await provider.acquire(request(base.appendingPathComponent(path)))
        Issue.record("Expected provider failure")
      }
      catch let error as TokenProviderError {
        #expect(error.reason == reason)
        #expect(!error.description.contains("SECRET"))
      }
    }
  }

  private struct HTTPCorpus: Decodable {
    let formatVersion: Int
    let cases: [HTTPCase]
  }

  private struct HTTPCase: Decodable, Sendable {
    let id: String
    let target: String
    let status: Int
    let headers: [String: String]
    let body: String
    let expected: String
  }

  @Test func sharedHTTPFixtures() async throws {
    let url = try #require(Bundle.module.url(forResource: "oauth-http-cases", withExtension: "json"))
    let corpus = try JSONDecoder().decode(HTTPCorpus.self, from: Data(contentsOf: url))
    #expect(corpus.formatVersion == 1)
    for fixture in corpus.cases {
      let calls = Mutex(0)
      let server = try RoutingHTTPServer(port: .any, localOnly: true) {
        Path("/response") {
          GET { _, res in
            calls.withLock { $0 += 1 }
            res.send(status: .init(code: fixture.status, info: "Fixture"),
                     headers: fixture.headers.mapValues { [$0] }, body: Data(fixture.body.utf8))
          }
          POST { _, res in
            calls.withLock { $0 += 1 }
            res.send(status: .init(code: fixture.status, info: "Fixture"),
                     headers: fixture.headers.mapValues { [$0] }, body: Data(fixture.body.utf8))
          }
        }
      }
      let base = try await start(server)
      defer { server.stop() }
      let provider = try URLSessionOAuthTokenProvider(configuration: .init(
        identity: "app", clientID: "client", clientSecret: "secret", authentication: .clientSecretPost,
        issuer: "https://trusted.example"
      ))
      let endpoint = base.appendingPathComponent("response")
      let request = request(endpoint, discovery: fixture.target == "discovery" ? endpoint.absoluteString : nil)
      for refresh in [false, true] {
        do {
          if refresh {
            _ = try await provider.refresh(request, refreshToken: "refresh-secret")
          }
          else { _ = try await provider.acquire(request) }
          Issue.record("Expected provider failure for \(fixture.id)")
        }
        catch let error as TokenProviderError {
          let expected: TokenProviderError.Reason = fixture.expected == "temporary" ? .temporary :
            (fixture.expected == "invalid_grant" ? .invalidGrant : .unavailable)
          #expect(error.reason == expected, "\(fixture.id)")
          #expect(!error.description.contains("SECRET"))
        }
      }
      #expect(calls.withLock { $0 } == 2, "\(fixture.id)")
    }
  }

}
