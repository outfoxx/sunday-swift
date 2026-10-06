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

/// OAuth credentials narrowed to a supported acquisition flow.
public enum OAuthCredentials: OAuthCredential, CustomStringConvertible, CustomDebugStringConvertible {
  /// Service credentials with an installed module adapter that does not acquire tokens.
  case clientCredentials(
    OAuthConfiguration,
    providerFactory: @Sendable (OAuthConfiguration) throws -> any TokenProvider
  )
  /// PKCE credentials with an installed module adapter that does not acquire tokens.
  case authorizationCode(
    OAuthConfiguration,
    providerFactory: @Sendable (OAuthConfiguration) throws -> any TokenProvider
  )

  /// Application client/session inputs, independent of the HTTP implementation.
  public var configuration: OAuthConfiguration {
    switch self {
    case .clientCredentials(let value, _), .authorizationCode(let value, _): return value
    }
  }

  func makeProvider(baseURL: URL) throws -> any TokenProvider {
    switch self {
    case .clientCredentials(let value, let factory), .authorizationCode(let value, let factory):
      func endpoint(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard !value.contains("{"), !value.contains("}"), let url = URL(string: value, relativeTo: baseURL) else {
          throw TokenProviderError()
        }
        return url.absoluteURL.absoluteString
      }
      let endpoints = try SecurityEndpoints(
        discoveryURL: endpoint(value.endpoints.discoveryURL),
        authorizationURL: endpoint(value.endpoints.authorizationURL),
        tokenURL: endpoint(value.endpoints.tokenURL),
        refreshURL: endpoint(value.endpoints.refreshURL)
      )
      return try factory(.init(
        identity: value.identity,
        clientID: value.clientID,
        clientSecret: value.clientSecret,
        authentication: value.authentication,
        grantIdentity: value.grantIdentity,
        endpoints: endpoints,
        issuer: value.issuer,
        authorize: value.authorize
      ))
    }
  }

  var flow: SecurityBinding.Flow {
    switch self {
    case .clientCredentials: return .clientCredentials
    case .authorizationCode: return .authorizationCode
    }
  }

  public var description: String { "OAuthCredentials()" }
  public var debugDescription: String { description }
}
