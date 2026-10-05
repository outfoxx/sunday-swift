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

import CryptoKit
import AppAuthCore
import Foundation

/// OAuth acquisition using a dedicated URLSession without ambient credentials, cookies, or redirect replay.
public actor URLSessionOAuthTokenProvider: RefreshingTokenProvider {
  /// Explicit client authentication. Public clients use `none` with application-managed PKCE.
  public enum Authentication: String, Sendable {
    case none
    case clientSecretBasic = "client_secret_basic"
    case clientSecretPost = "client_secret_post"
  }

  /// Secret application configuration; none of these credentials belong in generated metadata.
  public struct Configuration: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let identity: String
    public let clientID: String
    public let clientSecret: String?
    public let authentication: Authentication
    public let grantIdentity: String?
    public let endpoints: SecurityEndpoints
    public let issuer: String?
    public let authorize: (@Sendable (TokenRequest) async throws -> AuthorizationGrant)?

    /// Configures a client and, for discovery, an independently trusted exact issuer.
    public init(
      identity: String, clientID: String, clientSecret: String? = nil, authentication: Authentication = .none,
      grantIdentity: String? = nil, endpoints: SecurityEndpoints = .init(), issuer: String? = nil,
      authorize: (@Sendable (TokenRequest) async throws -> AuthorizationGrant)? = nil
    ) {
      self.identity = identity
      self.clientID = clientID
      self.clientSecret = clientSecret
      self.authentication = authentication
      self.grantIdentity = grantIdentity
      self.endpoints = endpoints
      self.issuer = issuer
      self.authorize = authorize
    }

    public var description: String { "OAuthConfiguration()" }
    public var debugDescription: String { description }
  }

  public nonisolated var identity: String { configuration.identity }
  private nonisolated let configuration: Configuration
  private let session: URLSession
  private let now: @Sendable () -> Date
  private var consumedCodes: Set<Data> = []

  /// Creates an isolated acquisition session; its configuration may provide custom protocol classes for testing.
  public init(
    configuration: Configuration, sessionConfiguration: URLSessionConfiguration = .ephemeral,
    now: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    guard sessionConfiguration.identifier == nil else { throw TokenProviderError() }
    self.configuration = configuration
    self.now = now
    // Copy before removing ambient state so caller-owned configuration stays unchanged.
    guard let isolated = sessionConfiguration.copy() as? URLSessionConfiguration else { throw TokenProviderError() }
    isolated.httpAdditionalHeaders = nil
    isolated.httpCookieStorage = nil
    isolated.httpShouldSetCookies = false
    isolated.urlCredentialStorage = nil
    isolated.urlCache = nil
    session = URLSession(configuration: isolated, delegate: OAuthSessionDelegate(), delegateQueue: nil)
  }

  deinit { session.invalidateAndCancel() }

  public nonisolated func configure(_ binding: SecurityBinding) -> TokenConfiguration {
    TokenConfiguration(
      clientIdentity: configuration.clientID,
      grantIdentity: configuration.grantIdentity,
      endpoints: configuration.endpoints
    )
  }

  public func acquire(_ request: TokenRequest) async throws -> TokenSet {
    do {
      let request = try await resolved(request)
      var form = parameters(request)
      switch request.binding.flow {
      case .clientCredentials:
        guard configuration.authentication != .none else { throw TokenProviderError() }
        form["grant_type"] = "client_credentials"
      case .authorizationCode:
        guard consumedCodes.count < 1024, let authorize = configuration.authorize else {
          throw AuthorizationRequiredError()
        }
        let grant = try await authorize(request)
        guard !grant.code.isEmpty, !grant.redirectURI.isEmpty,
              (43 ... 128).contains(grant.codeVerifier.utf8.count),
              grant.codeVerifier.utf8.allSatisfy({ Self.verifierCharacters.contains($0) })
        else {
          throw TokenProviderError()
        }
        let digest = Data(SHA256.hash(data: Data(grant.code.utf8)))
        guard consumedCodes.count < 1024, consumedCodes.insert(digest).inserted else {
          throw AuthorizationRequiredError()
        }
        form["grant_type"] = "authorization_code"
        form["code"] = grant.code
        form["redirect_uri"] = grant.redirectURI
        form["code_verifier"] = grant.codeVerifier
      case .external, .static:
        throw TokenProviderError()
      }
      return try await exchange(request, form: form, refreshing: false)
    }
    catch { throw safe(error) }
  }

  public func refresh(_ request: TokenRequest, refreshToken: String) async throws -> TokenSet {
    do {
      guard !refreshToken.isEmpty else { throw TokenProviderError() }
      let request = try await resolved(request)
      var form = parameters(request)
      form["grant_type"] = "refresh_token"
      form["refresh_token"] = refreshToken
      return try await exchange(request, form: form, refreshing: true)
    }
    catch { throw safe(error) }
  }

  private func parameters(_ request: TokenRequest) -> [String: String] {
    var result: [String: String] = [:]
    if !request.binding.scopes.isEmpty { result["scope"] = request.binding.scopes.sorted().joined(separator: " ") }
    result["audience"] = request.binding.audience
    result["resource"] = request.binding.resource
    return result
  }

  private func exchange(_ request: TokenRequest, form: [String: String], refreshing: Bool) async throws -> TokenSet {
    try Task.checkCancellation()
    guard let selected = (refreshing ? request.binding.endpoints.refreshURL : nil) ??
      request.binding.endpoints.tokenURL else { throw TokenProviderError() }
    let endpoint = try OAuthWire.endpoint(selected)
    try validateClient()
    let standardFields = ["grant_type", "code", "redirect_uri", "scope", "refresh_token", "code_verifier"]
    var extras = form.filter { !standardFields.contains($0.key) }
    if configuration.authentication == .clientSecretPost {
      extras["client_secret"] = configuration.clientSecret
    }
    // The authorization endpoint is unused by a token request; the selected token URL
    // also supports direct-token configurations that do not have discovery metadata.
    let service = OIDServiceConfiguration(authorizationEndpoint: endpoint, tokenEndpoint: endpoint)
    let protocolRequest = OIDTokenRequest(
      configuration: service, grantType: form["grant_type"]!, authorizationCode: form["code"],
      redirectURL: form["redirect_uri"].flatMap(URL.init(string:)), clientID: configuration.clientID,
      clientSecret: configuration.authentication == .clientSecretBasic ? configuration.clientSecret : nil,
      scope: form["scope"], refreshToken: form["refresh_token"], codeVerifier: form["code_verifier"],
      additionalParameters: extras
    )
    var native = protocolRequest.urlRequest()
    native.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: native)
    guard let http = response as? HTTPURLResponse else { throw TokenProviderError() }
    try Self.checkAvailability(http.statusCode)
    guard http.statusCode == 200 else {
      let code = try? JSONDecoder().decode(OAuthWire.Failure.self, from: data).code
      if code == "invalid_grant" {
        if request.binding.flow == .authorizationCode { throw AuthorizationRequiredError() }
        throw TokenProviderError(reason: .invalidGrant)
      }
      if code == "temporarily_unavailable" || code == "server_error" { throw TokenProviderError(reason: .temporary) }
      throw TokenProviderError()
    }
    return try decodeToken(data, scopes: request.binding.scopes)
  }

  private func decodeToken(_ data: Data, scopes: Set<String>) throws -> TokenSet {
    try JSONDecoder().decode(OAuthWire.Success.self, from: data).tokens(scopes: scopes, now: now())
  }

  private func resolved(_ request: TokenRequest) async throws -> TokenRequest {
    try Task.checkCancellation()
    try validateClient()
    var endpoints = request.binding.endpoints
    if let discoveryURL = endpoints.discoveryURL {
      guard let issuer = configuration.issuer, !issuer.isEmpty else { throw TokenProviderError() }
      let discovery = try await discover(discoveryURL)
      guard discovery.issuer == issuer else { throw TokenProviderError() }
      if configuration.authentication != .none || request.binding.flow != .authorizationCode {
        guard (discovery.authenticationMethods ?? [Authentication.clientSecretBasic.rawValue])
          .contains(configuration.authentication.rawValue) else { throw TokenProviderError() }
      }
      endpoints = SecurityEndpoints(
        authorizationURL: discovery.authorizationEndpoint, tokenURL: discovery.tokenEndpoint
      )
        .overridden(by: endpoints)
      if request.binding.flow == .authorizationCode, endpoints.authorizationURL == nil { throw TokenProviderError() }
    }
    guard let tokenURL = endpoints.tokenURL else { throw TokenProviderError() }
    _ = try OAuthWire.endpoint(tokenURL)
    for value in [endpoints.authorizationURL, endpoints.refreshURL].compactMap({ $0 }) {
      _ = try OAuthWire.endpoint(value)
    }
    return TokenRequest(
      binding: request.binding.overridingEndpoints(endpoints), clientIdentity: request.clientIdentity,
      grantIdentity: request.grantIdentity
    )
  }

  private func validateClient() throws {
    guard !configuration.clientID.isEmpty else { throw TokenProviderError() }
    if configuration.authentication != .none {
      guard let secret = configuration.clientSecret, !secret.isEmpty else { throw TokenProviderError() }
    }
  }

  private func discover(_ url: String) async throws -> OAuthWire.Discovery {
    var native = try URLRequest(url: OAuthWire.endpoint(url))
    native.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: native)
    guard let http = response as? HTTPURLResponse else { throw TokenProviderError() }
    try Self.checkAvailability(http.statusCode)
    guard http.statusCode == 200 else { throw TokenProviderError() }
    return try JSONDecoder().decode(OAuthWire.Discovery.self, from: data)
  }

  private static let verifierCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

  private static func checkAvailability(_ status: Int) throws {
    if status == 408 || status == 429 || (500 ... 599).contains(status) { throw TokenProviderError(reason: .temporary) }
  }

  private func safe(_ error: any Error) -> any Error {
    if error is CancellationError || Task.isCancelled { return CancellationError() }
    if error is AuthorizationRequiredError { return AuthorizationRequiredError() }
    if let error = error as? TokenProviderError { return error }
    if let error = error as? URLError,
       [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed,
        .notConnectedToInternet, .resourceUnavailable,
       ].contains(error.code) {
      return TokenProviderError(reason: .temporary)
    }
    return TokenProviderError()
  }


}

private final class OAuthSessionDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? { nil }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge
  ) async ->
    (URLSession.AuthChallengeDisposition, URLCredential?) {
    (
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ?
        .performDefaultHandling : .cancelAuthenticationChallenge,
      nil
    )
  }
}
