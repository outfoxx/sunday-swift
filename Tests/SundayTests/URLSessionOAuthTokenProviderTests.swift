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

}
