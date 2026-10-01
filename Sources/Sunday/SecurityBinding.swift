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

/// A logical wire scheme and application provider chosen for one operation.
public struct SecurityBinding: Sendable, Hashable, Codable {
  /// Supported acquisition contracts; browser authorization remains application-owned.
  public enum Flow: String, Sendable, Codable {
    case clientCredentials, authorizationCode, external, `static`
  }

  /// Placement of a provider credential on the HTTP request.
  public struct CredentialTransport: Sendable, Hashable, Codable {
    /// Supported wire locations.
    public enum Location: String, Sendable, Codable { case header, query, cookie }
    public let location: Location
    public let name: String
    public let prefix: String?

    /// Declares the wire location and optional HTTP authentication scheme.
    public init(location: Location, name: String, prefix: String? = nil) {
      self.location = location
      self.name = name
      self.prefix = prefix
    }
  }

  public let scheme: String
  public let provider: String
  public let flow: Flow
  public let profile: String?
  public let scopes: Set<String>
  public let endpoints: SecurityEndpoints
  public let audience: String?
  public let resource: String?
  public let transport: CredentialTransport

  /// Creates a deployment binding without embedding credentials in generated code.
  public init(
    scheme: String, provider: String, flow: Flow = .external, profile: String? = nil,
    scopes: Set<String> = [], endpoints: SecurityEndpoints = .init(), audience: String? = nil,
    resource: String? = nil, transport: CredentialTransport
  ) {
    self.scheme = scheme
    self.provider = provider
    self.flow = flow
    self.profile = profile
    self.scopes = scopes
    self.endpoints = endpoints
    self.audience = audience
    self.resource = resource
    self.transport = transport
  }

  func overridingEndpoints(_ overrides: SecurityEndpoints) -> Self {
    Self(
      scheme: scheme,
      provider: provider,
      flow: flow,
      profile: profile,
      scopes: scopes,
      endpoints: endpoints.overridden(by: overrides),
      audience: audience,
      resource: resource,
      transport: transport
    )
  }
}
