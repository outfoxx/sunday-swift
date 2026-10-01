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

/// Application storage for credentials. Use a secure store when persistence is required.
public protocol TokenStore: Sendable {
  /// Loads credentials for the opaque cache identity.
  func load(key: String) async throws -> TokenSet?
  /// Atomically replaces credentials, including any rotated refresh token.
  func save(key: String, tokens: TokenSet) async throws
  /// Removes credentials during application-managed logout or revocation.
  func remove(key: String) async throws
}

actor MemoryTokenStore: TokenStore {
  private var tokens: [String: TokenSet] = [:]
  func load(key: String) -> TokenSet? { tokens[key] }
  func save(key: String, tokens: TokenSet) { self.tokens[key] = tokens }
  func remove(key: String) { tokens.removeValue(forKey: key) }
}
