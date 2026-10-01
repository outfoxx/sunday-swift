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

/// Starts a test listener without blocking Swift's cooperative executor.
/// The custom start operation also supports the Bonjour locator's synchronous API.
func startTestServer(
  _ server: RoutingHTTPServer,
  timeout: TimeInterval = 30,
  using start: @escaping @Sendable (RoutingHTTPServer, TimeInterval) -> URL? = { $0.startLocal(timeout: $1) }
) async throws -> URL {
  try await withTaskCancellationHandler {
    try Task.checkCancellation()
    let url = await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: start(server, timeout))
      }
    }
    try Task.checkCancellation()
    guard let url else {
      let failure = TestServerStartError(timeout: timeout, listenerState: String(describing: server.state))
      server.stop()
      throw failure
    }
    return url
  } onCancel: {
    server.stop()
  }
}

/// Works with both XCTest and Swift Testing without recording an issue in the wrong framework.
struct TestServerStartError: Error, CustomStringConvertible {
  let timeout: TimeInterval
  let listenerState: String

  var description: String {
    "Test HTTP server failed to start within \(timeout)s; listener state: \(listenerState)"
  }
}
