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
    let endpoint = try await tokenEndpoint(request, refreshing: refreshing)
    var native = URLRequest(url: endpoint)
    native.httpMethod = "POST"
    native.setValue("application/json", forHTTPHeaderField: "Accept")
    native.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var form = form
    guard !configuration.clientID.isEmpty else { throw TokenProviderError() }
    switch configuration.authentication {
    case .none:
      form["client_id"] = configuration.clientID
    case .clientSecretBasic, .clientSecretPost:
      guard let secret = configuration.clientSecret, !secret.isEmpty else { throw TokenProviderError() }
      if configuration.authentication == .clientSecretBasic {
        let encoded = Self.encode(configuration.clientID) + ":" + Self.encode(secret)
        native.setValue("Basic " + Data(encoded.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
      }
      else {
        form["client_id"] = configuration.clientID
        form["client_secret"] = secret
      }
    }
    native.httpBody = Data(
      form.keys.sorted().map { Self.encode($0) + "=" + Self.encode(form[$0]!) }
        .joined(separator: "&").utf8
    )
    let (data, response) = try await session.data(for: native)
    guard let http = response as? HTTPURLResponse else { throw TokenProviderError() }
    try Self.checkAvailability(http.statusCode)
    guard (200 ..< 300).contains(http.statusCode) else {
      let code = try? JSONDecoder().decode(ErrorResponse.self, from: data).error
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
    let token = try JSONDecoder().decode(TokenResponse.self, from: data)
    guard !token.accessToken.isEmpty, token.tokenType.lowercased() == "bearer",
          token.refreshToken.map({ !$0.isEmpty }) ?? true else { throw TokenProviderError() }
    if let scope = token.scope,
       !scopes.isSubset(of: Set(scope.split(separator: " ").map(String.init))) {
      throw TokenProviderError()
    }
    var expiresAt: Date?
    if let seconds = token.expiresIn {
      let expiry = now().addingTimeInterval(seconds)
      guard seconds.isFinite, seconds > 0, expiry.timeIntervalSince1970.isFinite else { throw TokenProviderError() }
      expiresAt = expiry
    }
    return TokenSet(accessToken: token.accessToken, expiresAt: expiresAt, refreshToken: token.refreshToken)
  }

  private func tokenEndpoint(_ request: TokenRequest, refreshing: Bool) async throws -> URL {
    var discovered: String?
    if let discoveryURL = request.binding.endpoints.discoveryURL {
      guard let issuer = configuration.issuer, !issuer.isEmpty else { throw TokenProviderError() }
      var native = try URLRequest(url: Self.endpoint(discoveryURL))
      native.setValue("application/json", forHTTPHeaderField: "Accept")
      let (data, response) = try await session.data(for: native)
      guard let http = response as? HTTPURLResponse else { throw TokenProviderError() }
      try Self.checkAvailability(http.statusCode)
      guard (200 ..< 300).contains(http.statusCode) else { throw TokenProviderError() }
      let discovery = try JSONDecoder().decode(Discovery.self, from: data)
      guard discovery.issuer == issuer,
            (discovery.authenticationMethods ?? [Authentication.clientSecretBasic.rawValue])
            .contains(configuration.authentication.rawValue) else { throw TokenProviderError() }
      discovered = discovery.tokenEndpoint
    }
    guard let selected = (refreshing ? request.binding.endpoints.refreshURL : nil) ??
      request.binding.endpoints.tokenURL ?? discovered else { throw TokenProviderError() }
    return try Self.endpoint(selected)
  }

  private static func endpoint(_ raw: String) throws -> URL {
    guard let parts = URLComponents(string: raw), let host = parts.host, !host.isEmpty,
          parts.user == nil, parts.password == nil, parts.fragment == nil,
          parts
          .scheme == "https" || (parts.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)),
          let url = parts.url else { throw TokenProviderError() }
    return url
  }

  private static let verifierCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

  private static func encode(_ value: String) -> String {
    value.utf8.map { byte in
      if verifierCharacters.contains(byte), byte != 126 { return String(UnicodeScalar(byte)) }
      if byte == 32 { return "+" }
      return String(format: "%%%02X", byte)
    }.joined()
  }

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

  private struct ErrorResponse: Decodable { let error: String }

  private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Double?
    let refreshToken: String?
    let scope: String?
    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token", tokenType = "token_type", expiresIn = "expires_in"
      case refreshToken = "refresh_token", scope
    }
  }

  private struct Discovery: Decodable {
    let issuer: String
    let tokenEndpoint: String
    let authenticationMethods: [String]?
    enum CodingKeys: String, CodingKey {
      case issuer, tokenEndpoint = "token_endpoint", authenticationMethods = "token_endpoint_auth_methods_supported"
    }
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
