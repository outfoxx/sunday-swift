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

/// Application-owned credentials. Providers own acquisition, caching, and rejection recovery.
public protocol TokenProvider: Sendable {
  /// Non-secret identity distinguishing provider configurations.
  var identity: String { get }
  /// Supplies client and authorization-session identities without exposing credentials to generated code.
  func configure(_ binding: SecurityBinding) throws -> TokenConfiguration
  /// Acquires credentials; interactive flows must use a fresh application authorization.
  func acquire(_ request: TokenRequest) async throws -> TokenSet
  /// Obtains a credential receipt for one request attempt, without implicit caching.
  func credentials(for binding: SecurityBinding) async throws -> TokenLease
  /// Rejects only the supplied token in its original session. Return false when recovery is unsupported.
  func reject(_ request: TokenRequest, rejectedToken: String) async throws -> Bool
}

/// Optional refresh capability with support for refresh-token rotation.
public protocol RefreshingTokenProvider: TokenProvider {
  /// Returns replacement credentials. Omit the refresh token only when the existing token remains valid.
  func refresh(_ request: TokenRequest, refreshToken: String) async throws -> TokenSet
}

public extension TokenProvider {
  /// Resolves application configuration and acquires once. Retains context only for this attempt's rejection.
  func credentials(for binding: SecurityBinding) async throws -> TokenLease {
    do {
      try Task.checkCancellation()
      let configuration = try configure(binding)
      guard !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !configuration.clientIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw TokenProviderError()
      }
      let request = TokenRequest(
        binding: binding.overridingEndpoints(configuration.endpoints),
        clientIdentity: configuration.clientIdentity, grantIdentity: configuration.grantIdentity
      )
      let tokens = try await acquire(request)
      try Task.checkCancellation()
      guard !tokens.accessToken.isEmpty,
            tokens.expiresAt.map({ $0.timeIntervalSince1970.isFinite && $0 > Date() }) ?? true else {
        throw TokenProviderError()
      }
      return TokenLease(key: "", tokens: tokens) {
        try await self.reject(request, rejectedToken: tokens.accessToken)
      }
    }

    catch let error where isRequestCancellation(error) {
      throw error
    }

    catch let error as TokenProviderError {
      throw error
    }

    catch { throw TokenProviderError() }
  }

  /// Providers without rejection recovery leave the response to the caller.
  func reject(_: TokenRequest, rejectedToken _: String) async throws -> Bool { false }
}
