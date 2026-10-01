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

/// Acquisition endpoints, independent of profile and resource-server trust.
public struct SecurityEndpoints: Sendable, Hashable, Codable {
  public let discoveryURL: String?
  public let authorizationURL: String?
  public let tokenURL: String?
  public let refreshURL: String?

  /// Creates acquisition endpoints. Missing overrides inherit the generated binding.
  public init(
    discoveryURL: String? = nil,
    authorizationURL: String? = nil,
    tokenURL: String? = nil,
    refreshURL: String? = nil
  ) {
    self.discoveryURL = discoveryURL
    self.authorizationURL = authorizationURL
    self.tokenURL = tokenURL
    self.refreshURL = refreshURL
  }

  /// Applies deployment overrides without changing provider, profile, issuer, or audience.
  public func overridden(by other: Self) -> Self {
    Self(
      discoveryURL: other.discoveryURL ?? discoveryURL,
      authorizationURL: other.authorizationURL ?? authorizationURL,
      tokenURL: other.tokenURL ?? tokenURL,
      refreshURL: other.refreshURL ?? refreshURL
    )
  }
}
