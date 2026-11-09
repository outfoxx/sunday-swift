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
import Synchronization

// One owner per invocation (including every connection of an event subscription).
final class AuthenticationRecoveryBudget: Sendable {
  private let used = Mutex(false)
  func shouldRetry(_ response: HTTPURLResponse, for request: URLRequest) -> Bool {
    guard response.statusCode == 401, ["GET", "HEAD", "OPTIONS"].contains(request.httpMethod ?? "GET"),
          request.httpBody?.isEmpty ?? true, request.httpBodyStream == nil,
          BearerChallenge.token(in: request.value(forHTTPHeaderField: "Authorization")) != nil,
          BearerChallenge.isInvalidToken(response.value(forHTTPHeaderField: "WWW-Authenticate") ?? "") else {
      return false
    }
    return consume()
  }

  private func consume() -> Bool {
    used.withLock {
      guard !$0 else { return false }
      $0 = true
      return true
    }
  }
}
