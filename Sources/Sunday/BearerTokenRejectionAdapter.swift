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

/// Opt-in stop policy for explicit bearer rejection. Does not acquire, invalidate, refresh, or replay.
public struct BearerTokenRejectionAdapter: ResponseAdapter {
  /// Creates a stateless policy. Compose after provider rejection feedback when both are installed.
  public init() {}

  /// Leaves unrelated responses and their bodies untouched.
  public func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
    let challenge = response.value(forHTTPHeaderField: "WWW-Authenticate") ?? ""
    guard response.statusCode == 401,
          BearerChallenge.token(in: request.value(forHTTPHeaderField: "Authorization")) != nil,
          BearerChallenge.isInvalidToken(challenge) else { return response }
    throw TokenRejectedError(response: response)
  }
}
