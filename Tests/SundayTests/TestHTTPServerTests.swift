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
import SundayServer
import Testing

struct TestHTTPServerTests {
  @Test func concurrentStartupWaitsForReadyListeners() async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 16 {
        group.addTask {
          let server = try RoutingHTTPServer(port: .any, localOnly: true)
          defer { server.stop() }
          let url = try await startTestServer(server)
          #expect(server.isReady)
          #expect(url.port != nil)
        }
      }
      try await group.waitForAll()
    }
  }

  @Test @MainActor func synchronousStartupDoesNotBlockTheCallingActor() async throws {
    let server = try RoutingHTTPServer(port: .any, localOnly: true)
    defer { server.stop() }
    let released = DispatchSemaphore(value: 0)
    _ = try await startTestServer(server) { server, timeout in
      Task { @MainActor in
        released.signal()
      }
      // A synchronous call on MainActor would prevent this signal until the wait expires.
      guard released.wait(timeout: .now() + 5) == .success else { return nil }
      return server.startLocal(timeout: timeout)
    }
    #expect(server.isReady)
  }

  @Test func stoppedListenerReportsItsState() async throws {
    let server = try RoutingHTTPServer(port: .any, localOnly: true)
    server.stop()
    do {
      _ = try await startTestServer(server, timeout: 0.1)
      Issue.record("Expected startup to fail")
    }
    catch let error as TestServerStartError {
      #expect(error.timeout == 0.1)
      #expect(error.listenerState.contains("cancelled"))
      #expect(error.description.contains("listener state"))
    }
  }

  @Test func failedStartupStopsTheListener() async throws {
    let server = try RoutingHTTPServer(port: .any, localOnly: true)
    await #expect(throws: TestServerStartError.self) {
      try await startTestServer(server) { _, _ in nil }
    }
    #expect(server.state == .cancelled)
  }

  @Test func cancellationStopsPendingStartup() async throws {
    let server = try RoutingHTTPServer(port: .any, localOnly: true)
    let started = AsyncStream.makeStream(of: Void.self)
    let gate = DispatchSemaphore(value: 0)
    let caller = Task {
      try await startTestServer(server) { server, timeout in
        started.continuation.yield(())
        // Bound the synthetic blocking operation so a broken cancellation path cannot hang the suite.
        _ = gate.wait(timeout: .now() + 5)
        return server.startLocal(timeout: timeout)
      }
    }
    for await _ in started.stream { break }
    caller.cancel()
    #expect(server.state == .cancelled)
    gate.signal()
    started.continuation.finish()
    await #expect(throws: CancellationError.self) { try await caller.value }
  }
}
