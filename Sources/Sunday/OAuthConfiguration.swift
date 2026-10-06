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

/// Secret application configuration; none of these credentials belong in generated metadata.
public struct OAuthConfiguration: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public let identity: String
  public let clientID: String
  public let clientSecret: String?
  public let authentication: OAuthAuthentication
  public let grantIdentity: String?
  public let endpoints: SecurityEndpoints
  public let issuer: String?
  public let authorize: (@Sendable (TokenRequest) async throws -> AuthorizationGrant)?

  /// Configures a client and, for discovery, an independently trusted exact issuer.
  public init(
    identity: String, clientID: String, clientSecret: String? = nil, authentication: OAuthAuthentication = .none,
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
