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

/// Shared credential cache with coalesced renewal and cancellation of unneeded acquisition.
public actor TokenManager {
  private let providers: [String: any TokenProvider]
  private let store: any TokenStore
  private let expirySkew: TimeInterval
  private let now: @Sendable () -> Date
  private var entries: [String: TokenCacheEntry] = [:]
  private var closed = false

  /// Creates a manager shared by transports using the same application identities.
  public init(
    providers: [String: any TokenProvider],
    store: (any TokenStore)? = nil,
    expirySkew: TimeInterval = 30,
    now: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    guard expirySkew.isFinite, expirySkew >= 0 else { throw TokenProviderError() }
    self.providers = providers
    self.store = store ?? MemoryTokenStore()
    self.expirySkew = expirySkew
    self.now = now
  }

  /// Returns current credentials, renewing once for all callers with the same cache identity.
  public func credentials(for binding: SecurityBinding) async throws -> TokenLease {
    try Task.checkCancellation()
    guard !closed else { throw TokenProviderError() }
    let resolved = try resolve(binding)
    let key = resolved.key
    let entry = entries[key] ?? TokenCacheEntry(key: key, store: store, expirySkew: expirySkew, now: now)
    entries[key] = entry
    return try await entry.credentials(provider: resolved.provider, request: resolved.request)
  }

  /// Expires only the rejected credential while retaining refresh state and concurrent replacements.
  public func invalidate(_ lease: TokenLease) async throws {
    guard !closed else { throw TokenProviderError() }
    try await entries[lease.key]?.invalidate(lease)
  }

  /// Cancels acquisition without discarding a refresh rotation already being committed to storage.
  public func close() async {
    closed = true
    for entry in entries.values {
      await entry.close()
    }
  }

  private func resolve(_ binding: SecurityBinding) throws -> Resolved {
    do {
      guard let provider = providers[binding.provider] else { throw TokenProviderError() }
      let config = try provider.configure(binding)
      guard !provider.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !config.clientIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            binding.flow != .authorizationCode || !(config.grantIdentity ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TokenProviderError() }
      let selected = binding.overridingEndpoints(config.endpoints)
      let request = TokenRequest(
        binding: selected,
        clientIdentity: config.clientIdentity,
        grantIdentity: config.grantIdentity
      )
      let key = CacheIdentity(
        provider: binding.provider,
        providerIdentity: provider.identity,
        clientIdentity: config.clientIdentity,
        grantIdentity: config.grantIdentity,
        profile: selected.profile,
        flow: selected.flow,
        endpoints: selected.endpoints,
        scopes: selected.scopes.sorted(),
        audience: selected.audience,
        resource: selected.resource
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      guard let encoded = String(data: try encoder.encode(key), encoding: .utf8) else { throw TokenProviderError() }
      return Resolved(key: encoded, provider: provider, request: request)
    }
    catch is CancellationError { throw CancellationError() }
 catch { throw TokenProviderError() }
  }

  private struct Resolved {
    let key: String
    let provider: any TokenProvider
    let request: TokenRequest
  }

  private struct CacheIdentity: Encodable {
    let provider: String
    let providerIdentity: String
    let clientIdentity: String
    let grantIdentity: String?
    let profile: String?
    let flow: SecurityBinding.Flow
    let endpoints: SecurityEndpoints
    let scopes: [String]
    let audience: String?
    let resource: String?
  }
}
