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

// Each cache identity has a serial storage gate in addition to actor isolation. Awaiting a
// provider or persistent store must not allow invalidation to overwrite a concurrent rotation.
actor TokenCacheEntry {
  private struct Renewal {
    let id: UUID
    let task: Task<Void, Never>
    var waiters: [UUID: CheckedContinuation<TokenLease, any Error>]
    var committing = false
  }

  private let key: String
  private let store: any TokenStore
  private let expirySkew: TimeInterval
  private let now: @Sendable () -> Date
  private var renewal: Renewal?
  private var authorizationAttempted = false
  private var gateHeld = false
  private var gateWaiters: [CheckedContinuation<Void, Never>] = []
  private var closed = false

  init(key: String, store: any TokenStore, expirySkew: TimeInterval, now: @escaping @Sendable () -> Date) {
    self.key = key
    self.store = store
    self.expirySkew = expirySkew
    self.now = now
  }

  func credentials(provider: any TokenProvider, request: TokenRequest) async throws -> TokenLease {
    let waiter = UUID()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard !closed else { throw TokenProviderError() }
      return try await withCheckedThrowingContinuation { continuation in
        if renewal != nil {
          renewal?.waiters[waiter] = continuation
        }
        else {
          let id = UUID()
          let task = Task { await performRenewal(id: id, provider: provider, request: request) }
          renewal = Renewal(id: id, task: task, waiters: [waiter: continuation])
        }
      }
    } onCancel: {
      Task { await self.cancel(waiter: waiter) }
    }
  }

  func invalidate(_ lease: TokenLease) async throws {
    await lock()
    defer { unlock() }
    do {
      try Task.checkCancellation()
      if let current = try await store.load(key: key), current.accessToken == lease.tokens.accessToken {
        try await store.save(key: key, tokens: TokenSet(
          accessToken: current.accessToken,
          expiresAt: .distantPast,
          refreshToken: current.refreshToken
        ))
      }
    }
    catch is CancellationError { throw CancellationError() }
 catch { throw TokenProviderError() }
  }

  func close() {
    closed = true
    guard let current = renewal else { return }
    for waiter in current.waiters.values {
      waiter.resume(throwing: CancellationError())
    }
    if !current.committing { current.task.cancel() }
    renewal = nil
  }

  private func cancel(waiter: UUID) {
    guard let continuation = renewal?.waiters.removeValue(forKey: waiter) else { return }
    continuation.resume(throwing: CancellationError())
    if let current = renewal, current.waiters.isEmpty, !current.committing {
      current.task.cancel()
      renewal = nil
    }
  }

  private func performRenewal(id: UUID, provider: any TokenProvider, request: TokenRequest) async {
    let result: Result<TokenLease, any Error>
    do { result = try .success(await renew(id: id, provider: provider, request: request)) }
 catch is CancellationError { result = .failure(CancellationError()) }
 catch is AuthorizationRequiredError { result = .failure(AuthorizationRequiredError()) }
 catch { result = .failure(TokenProviderError()) }
    guard let current = renewal, current.id == id else { return }
    renewal = nil
    for waiter in current.waiters.values {
      waiter.resume(with: result)
    }
  }

  private func renew(id: UUID, provider: any TokenProvider, request: TokenRequest) async throws -> TokenLease {
    await lock()
    defer { unlock() }
    try Task.checkCancellation()
    let stored = try await store.load(key: key)
    if let stored, stored.expiresAt == nil || stored.expiresAt! > now().addingTimeInterval(expirySkew) {
      return TokenLease(key: key, tokens: stored)
    }
    let tokens: TokenSet
    if let refreshToken = stored?.refreshToken, let refreshing = provider as? any RefreshingTokenProvider {
      let renewed = try await refreshing.refresh(request, refreshToken: refreshToken)
      tokens = TokenSet(
        accessToken: renewed.accessToken,
        expiresAt: renewed.expiresAt,
        refreshToken: renewed.refreshToken ?? refreshToken
      )
    }
    else {
      if request.binding.flow == .authorizationCode {
        guard stored == nil, !authorizationAttempted else { throw AuthorizationRequiredError() }
        authorizationAttempted = true
      }
      tokens = try await provider.acquire(request)
    }
    guard !tokens.accessToken.isEmpty,
          tokens.expiresAt.map({ $0.timeIntervalSince1970.isFinite && $0 > now() }) ?? true
    else {
      throw TokenProviderError()
    }
    if renewal?.id == id { renewal?.committing = true }
    // An unstructured save is deliberately independent of caller cancellation after rotation.
    let save = Task { try await store.save(key: key, tokens: tokens) }
    try await save.value
    return TokenLease(key: key, tokens: tokens)
  }

  private func lock() async {
    if gateHeld {
      await withCheckedContinuation { gateWaiters.append($0) }
    }
    else { gateHeld = true }
  }

  private func unlock() {
    if gateWaiters.isEmpty { gateHeld = false }
 else { gateWaiters.removeFirst().resume() }
  }
}
