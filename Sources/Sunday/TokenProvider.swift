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

/// Application-owned credential acquisition. Identity must distinguish provider configurations.
public protocol TokenProvider: Sendable {
  var identity: String { get }
  /// Supplies client and authorization-session identities without exposing credentials to generated code.
  func configure(_ binding: SecurityBinding) throws -> TokenConfiguration
  /// Acquires credentials; interactive flows must use a fresh application authorization.
  func acquire(_ request: TokenRequest) async throws -> TokenSet
}

/// Optional refresh capability with support for refresh-token rotation.
public protocol RefreshingTokenProvider: TokenProvider {
  /// Returns replacement credentials. Omit the refresh token only when the existing token remains valid.
  func refresh(_ request: TokenRequest, refreshToken: String) async throws -> TokenSet
}
