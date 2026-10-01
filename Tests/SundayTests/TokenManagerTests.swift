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
@testable import Sunday
import Synchronization
import Testing

struct TokenManagerTests {
  private let binding = SecurityBinding(
    scheme: "identity", provider: "identity", flow: .clientCredentials, profile: "external", scopes: ["read"],
    transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
  )

  private actor Provider: RefreshingTokenProvider {
    nonisolated let identity = "provider"
    nonisolated let configuration = Mutex(TokenConfiguration(clientIdentity: "client", grantIdentity: "session"))
    var acquired: [TokenRequest] = []
    var refreshed: [String] = []
    var token = TokenSet(accessToken: "initial", refreshToken: "first-refresh")
    var replacement = TokenSet(accessToken: "renewed", refreshToken: "rotated-refresh")
    var failure = false
    var delay: Duration = .zero
    var canceled = false
    let started = Signal()
    let stopped = Signal()

    nonisolated func configure(_ binding: SecurityBinding) -> TokenConfiguration { configuration.withLock { $0 } }

    func acquire(_ request: TokenRequest) async throws -> TokenSet {
      acquired.append(request)
      await started.open()
      do {
        try await Task.sleep(for: delay)
        if failure { throw NSError(domain: "secret-from-provider", code: 1) }
        return token
      }
      catch is CancellationError {
        canceled = true
        await stopped.open()
        throw CancellationError()
      }
    }

    func refresh(_ request: TokenRequest, refreshToken: String) throws -> TokenSet {
      refreshed.append(refreshToken)
      return replacement
    }

    func configureTokens(
      initial: TokenSet? = nil,
      replacement: TokenSet? = nil,
      delay: Duration = .zero,
      failure: Bool = false
    ) {
      if let initial { token = initial }
      if let replacement { self.replacement = replacement }
      self.delay = delay
      self.failure = failure
    }
  }

  private actor Signal {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
      if opened { return }
      await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
      opened = true
      for waiter in waiters {
        waiter.resume()
      }
      waiters.removeAll()
    }
  }

  private actor Store: TokenStore {
    var values: [String: TokenSet] = [:]
    var blockSaves = false
    let saving = Signal()
    let resumeSave = Signal()
    func load(key: String) -> TokenSet? { values[key] }
    func save(key: String, tokens: TokenSet) async {
      if blockSaves {
        await saving.open()
        await resumeSave.wait()
      }
      values[key] = tokens
    }

    func remove(key: String) { values.removeValue(forKey: key) }
    func block() { blockSaves = true }
  }

  @Test func cacheRotationAndConditionalInvalidation() async throws {
    let provider = Provider()
    let manager = try TokenManager(providers: ["identity": provider])
    let first = try await manager.credentials(for: binding)
    #expect(try await manager.credentials(for: binding).tokens == first.tokens)
    try await manager.invalidate(first)
    let renewed = try await manager.credentials(for: binding)
    #expect(renewed.tokens.accessToken == "renewed")
    #expect(renewed.tokens.refreshToken == "rotated-refresh")
    try await manager.invalidate(first)
    #expect(try await manager.credentials(for: binding).tokens == renewed.tokens)
    #expect(await provider.acquired.count == 1)
    #expect(await provider.refreshed == ["first-refresh"])
    await provider.configureTokens(replacement: TokenSet(accessToken: "next"))
    try await manager.invalidate(renewed)
    #expect(try await manager.credentials(for: binding).tokens.refreshToken == "rotated-refresh")
    #expect(!String(reflecting: renewed).contains("rotated-refresh"))
    await manager.close()
  }

  @Test func concurrentRenewalCoalesces() async throws {
    let provider = Provider()
    await provider.configureTokens(delay: .milliseconds(30))
    let manager = try TokenManager(providers: ["identity": provider])
    try await withThrowingTaskGroup(of: TokenLease.self) { group in
      for _ in 0 ..< 40 {
        group.addTask { try await manager.credentials(for: binding) }
      }
      for try await value in group {
        #expect(value.tokens.accessToken == "initial")
      }
    }
    #expect(await provider.acquired.count == 1)
    await manager.close()
  }

  @Test func cancelingLastCallerCancelsAcquisitionAndReturnsPromptly() async throws {
    let provider = Provider()
    await provider.configureTokens(delay: .seconds(120))
    let manager = try TokenManager(providers: ["identity": provider])
    let caller = Task { try await manager.credentials(for: binding) }
    await provider.started.wait()
    caller.cancel()
    await #expect(throws: CancellationError.self) { try await caller.value }
    await provider.stopped.wait()
    #expect(await provider.canceled)
    await manager.close()
  }

  @Test func cancelingOneCallerDoesNotCancelOtherWaiters() async throws {
    let provider = Provider()
    await provider.configureTokens(delay: .milliseconds(50))
    let manager = try TokenManager(providers: ["identity": provider])
    let canceled = Task { try await manager.credentials(for: binding) }
    await provider.started.wait()
    // The surviving call registers before a delayed cancellation while acquisition is suspended.
    let cancel = Task {
      try await Task.sleep(for: .milliseconds(10))
      canceled.cancel()
    }
    let surviving = try await manager.credentials(for: binding)
    try await cancel.value
    await #expect(throws: CancellationError.self) { try await canceled.value }
    #expect(surviving.tokens.accessToken == "initial")
    #expect(await provider.acquired.count == 1)
    #expect(await !provider.canceled)
    await manager.close()
  }

  @Test func cancellationCannotDiscardCompletedRotation() async throws {
    let provider = Provider()
    let store = Store()
    let manager = try TokenManager(providers: ["identity": provider], store: store)
    let first = try await manager.credentials(for: binding)
    try await manager.invalidate(first)
    await store.block()
    let caller = Task { try await manager.credentials(for: binding) }
    await store.saving.wait()
    caller.cancel()
    await #expect(throws: CancellationError.self) { try await caller.value }
    await store.resumeSave.open()
    #expect(try await manager.credentials(for: binding).tokens.refreshToken == "rotated-refresh")
    #expect(await provider.refreshed.count == 1)
    await manager.close()
  }

  @Test func authorizationCodeRequiresFreshGrantAfterFailureOrUnrefreshableSession() async throws {
    let provider = Provider()
    await provider.configureTokens(failure: true)
    let interactive = SecurityBinding(
      scheme: binding.scheme,
      provider: binding.provider,
      flow: .authorizationCode,
      transport: binding.transport
    )
    let manager = try TokenManager(providers: ["identity": provider])
    await #expect(throws: TokenProviderError.self) { try await manager.credentials(for: interactive) }
    await #expect(throws: AuthorizationRequiredError.self) { try await manager.credentials(for: interactive) }
    #expect(await provider.acquired.count == 1)
    provider.configuration.withLock { $0 = TokenConfiguration(clientIdentity: "client", grantIdentity: "new-session") }
    await provider.configureTokens(initial: TokenSet(accessToken: "fresh"))
    let token = try await manager.credentials(for: interactive)
    try await manager.invalidate(token)
    await #expect(throws: AuthorizationRequiredError.self) { try await manager.credentials(for: interactive) }
    #expect(await provider.acquired.count == 2)
    await manager.close()
  }

  @Test func cacheSeparatesAllEnvironmentInputsAndUsesDeploymentEndpoints() async throws {
    let provider = Provider()
    let manager = try TokenManager(providers: ["identity": provider, "alias": provider])
    let variants = [
      binding,
      SecurityBinding(
        scheme: "same",
        provider: "identity",
        flow: .clientCredentials,
        profile: "external",
        scopes: ["read"],
        transport: binding.transport
      ),
      SecurityBinding(
        scheme: "same",
        provider: "alias",
        flow: .clientCredentials,
        profile: "external",
        scopes: ["read"],
        transport: binding.transport
      ),
      SecurityBinding(scheme: "same", provider: "identity", profile: "internal", transport: binding.transport),
      SecurityBinding(scheme: "same", provider: "identity", scopes: ["write"], transport: binding.transport),
      SecurityBinding(scheme: "same", provider: "identity", audience: "audience", transport: binding.transport),
      SecurityBinding(scheme: "same", provider: "identity", resource: "resource", transport: binding.transport),
      SecurityBinding(
        scheme: "same",
        provider: "identity",
        endpoints: .init(tokenURL: "https://other/token"),
        transport: binding.transport
      ),
    ]
    for variant in variants {
      _ = try await manager.credentials(for: variant)
    }
    #expect(await provider.acquired.count == variants.count - 1)
    provider.configuration.withLock {
      $0 = TokenConfiguration(
        clientIdentity: "other",
        grantIdentity: "other-session",
        endpoints: .init(tokenURL: "https://deployment/token")
      )
    }
    _ = try await manager.credentials(for: binding)
    #expect(await provider.acquired.last?.binding.endpoints.tokenURL == "https://deployment/token")
    #expect(await provider.acquired.last?.binding.profile == "external")
    await manager.close()
  }

  @Test func expirySkewAndInvalidCredentials() async throws {
    let provider = Provider()
    let now = Date(timeIntervalSince1970: 1000)
    await provider.configureTokens(initial: TokenSet(
      accessToken: "short",
      expiresAt: now.addingTimeInterval(20),
      refreshToken: "refresh"
    ))
    let manager = try TokenManager(providers: ["identity": provider], now: { now })
    _ = try await manager.credentials(for: binding)
    #expect(try await manager.credentials(for: binding).tokens.accessToken == "renewed")
    await manager.close()
    for invalid in [TokenSet(accessToken: ""), TokenSet(accessToken: "expired", expiresAt: now)] {
      let invalidProvider = Provider()
      await invalidProvider.configureTokens(initial: invalid)
      let invalidManager = try TokenManager(providers: ["identity": invalidProvider], now: { now })
      await #expect(throws: TokenProviderError.self) { try await invalidManager.credentials(for: binding) }
      await invalidManager.close()
    }
    let missing = try TokenManager(providers: [:])
    await #expect(throws: TokenProviderError.self) { try await missing.credentials(for: binding) }
  }

  @Test func preCanceledCallsDoNotAcquire() async throws {
    let provider = Provider()
    let manager = try TokenManager(providers: ["identity": provider])
    let ready = Signal()
    let call = Task {
      await ready.wait()
      return try await manager.credentials(for: binding)
    }
    call.cancel()
    await ready.open()
    await #expect(throws: CancellationError.self) { try await call.value }
    #expect(await provider.acquired.isEmpty)
    await manager.close()
  }
}
