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

/// Application identity and deployment inputs used to partition the shared credential cache.
public struct TokenConfiguration: Sendable {
  public let clientIdentity: String
  public let grantIdentity: String?
  public let endpoints: SecurityEndpoints

  /// Uses a new grant identity after fresh application authorization; never use an authorization code as this identity.
  public init(clientIdentity: String, grantIdentity: String? = nil, endpoints: SecurityEndpoints = .init()) {
    self.clientIdentity = clientIdentity
    self.grantIdentity = grantIdentity
    self.endpoints = endpoints
  }
}
