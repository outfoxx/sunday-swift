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
import Sunday
import Synchronization
import Testing

struct ClientSettingsPersistenceTests {
  private func binding(_ profile: String = "development") -> SecurityBinding {
    SecurityBinding(
      scheme: "identity",
      provider: "resolved-provider",
      flow: .authorizationCode,
      profile: profile,
      transport: .init(location: .header, name: "Authorization", prefix: "Bearer")
    )
  }

  @Test func persistedSessionsRotationIsolationAndLogout() async throws {
    let store = Store()
    let state = State()
    let managers = Mutex<[TokenManager]>([])
    func settings(
      _ time: TimeInterval,
      session: String = "session",
      profile: String = "development",
      direct: Bool = false
    ) throws -> ClientSettings {
      let provider = Provider(session: session, time: time, state: state)
      let factory: TokenManagerFactory = { providers in
        state.counts.withLock { $0.factories += 1 }
        #expect(Set(providers.keys) == ["resolved-provider"])
        #expect(providers["resolved-provider"]?.identity == "application")
        let manager = try TokenManager(
          providers: providers,
          store: store,
          expirySkew: 5,
          now: { Date(timeIntervalSince1970: time) }
        )
        managers.withLock { $0.append(manager) }
        return manager
      }
      let base = try #require(URL(string: "https://api.example"))
      let credentials: [String: any Credentials] = ["identity": ProviderCredentials(provider: provider)]
      if direct {
        return try ClientSettings(
          baseURL: base,
          bindings: ["read": [binding(profile)]],
          credentials: credentials,
          tokenManagerFactory: factory
        )
      }
      return try ClientSettings.resolve(
        baseURL: base,
        alternatives: ["read": [[binding(profile)]], "other": [[binding(profile)]], "public": [[]]],
        credentials: credentials,
        tokenManagerFactory: factory
      )
    }
    func token(_ settings: ClientSettings) async throws -> TokenSet {
      let manager = try #require(settings.tokenManager)
      return try await manager.credentials(for: #require(settings.bindings["read"]?.first)).tokens
    }
    do {
      let first = try settings(0)
      #expect(await store.reads == 0)
      #expect(state.counts.withLock { $0.factories == 1 && $0.acquisitions == 0 })
      let manager = try #require(first.tokenManager)
      let lease = try await manager.credentials(for: binding())
      #expect(lease.tokens.accessToken == "initial")
      await manager.close()
      #expect(try await token(settings(0, direct: true)).accessToken == "initial")
      #expect(state.counts.withLock { $0.acquisitions == 1 })
      let third = try settings(96)
      let configured = state.counts.withLock { $0.configurations }
      try await withThrowingTaskGroup(of: String.self) { group in
        let manager = try #require(third.tokenManager)
        let selected = binding()
        for _ in 0 ..< 20 {
          group.addTask { try await manager.credentials(for: selected).tokens.accessToken }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while state.counts.withLock({ $0.configurations < configured + 20 || $0.refreshes.isEmpty }),
              ContinuousClock.now < deadline {
          await Task.yield()
        }
        #expect(state.counts.withLock { $0.configurations >= configured + 20 && $0.refreshes.count == 1 })
        await state.refreshGate.open()
        for try await value in group {
          #expect(value == "rotated-1")
        }
      }
      #expect(state.counts.withLock { $0.refreshes == ["refresh-1"] })
      #expect(try await token(settings(96)).refreshToken == "refresh-2")
      _ = try await token(settings(192))
      #expect(state.counts.withLock { $0.refreshes == ["refresh-1", "refresh-2"] })
      #expect(await store.saves == 3)
      _ = try await token(settings(0, session: "other-session"))
      _ = try await token(settings(0, profile: "production"))
      #expect(state.counts.withLock { $0.acquisitions == 3 })
      let key = try #require(await store.initialKey)
      await store.remove(key: key)
      _ = try await token(settings(0))
      #expect(state.counts.withLock { $0.acquisitions == 4 })
    }
    catch {
      for manager in managers.withLock({ $0 }) {
        await manager.close()
      }
      throw error
    }
    for manager in managers.withLock({ $0 }) {
      await manager.close()
    }
  }

  @Test func publicInvalidAndFailingFactory() throws {
    let factory: TokenManagerFactory = { _ in throw Failure() }
    let base = try #require(URL(string: "https://api.example"))
    #expect(try ClientSettings(baseURL: base, tokenManagerFactory: factory).tokenManager == nil)
    #expect(try ClientSettings.resolve(
      baseURL: base,
      alternatives: ["public": [[]]],
      credentials: [:],
      tokenManagerFactory: factory
    ).tokenManager == nil)
    #expect(throws: TokenProviderError.self) {
      try ClientSettings(baseURL: base, bindings: ["read": [binding()]], tokenManagerFactory: factory)
    }
    #expect(throws: Failure.self) {
      try ClientSettings(
        baseURL: base,
        bindings: ["read": [binding()]],
        credentials: ["identity": ProviderCredentials(provider: Provider(session: "session", time: 0, state: State()))],
        tokenManagerFactory: factory
      )
    }
  }

  private struct Failure: Error {}
  private final class State: Sendable {
    struct Counts { var acquisitions = 0; var factories = 0
      var configurations = 0; var refreshes: [String] = []
    }

    let counts = Mutex(Counts())
    let refreshGate = Signal()
  }

  private struct Provider: RefreshingTokenProvider {
    let identity = "application"
    let session: String
    let time: TimeInterval
    let state: State
    func configure(_: SecurityBinding) -> TokenConfiguration {
      state.counts.withLock { $0.configurations += 1 }
      return .init(clientIdentity: "client", grantIdentity: session)
    }

    func acquire(_: TokenRequest) async throws -> TokenSet {
      state.counts.withLock { $0.acquisitions += 1 }
      return .init(accessToken: "initial", expiresAt: Date(timeIntervalSince1970: 100), refreshToken: "refresh-1")
    }

    func refresh(_: TokenRequest, refreshToken: String) async throws -> TokenSet {
      let count = state.counts.withLock { $0.refreshes.append(refreshToken); return $0.refreshes.count }
      if count == 1 { await state.refreshGate.wait() }
      return .init(
        accessToken: "rotated-\(count)",
        expiresAt: Date(timeIntervalSince1970: time + 100),
        refreshToken: "refresh-\(count + 1)"
      )
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
    var initialKey: String?
    var reads = 0
    var saves = 0
    func load(key: String) -> TokenSet? { reads += 1; return values[key] }
    func save(key: String, tokens: TokenSet) {
      if initialKey == nil { initialKey = key }; saves += 1; values[key] = tokens
    }

    func remove(key: String) { values.removeValue(forKey: key) }
  }
}
