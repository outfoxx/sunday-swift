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

/// Starts the synchronous test server without blocking Swift's cooperative executor.
func startTestServer(_ server: RoutingHTTPServer) async throws -> URL {
  let url = await withCheckedContinuation { continuation in
    DispatchQueue.global().async {
      continuation.resume(returning: server.startLocal(timeout: 5))
    }
  }
  return try #require(url)
}
