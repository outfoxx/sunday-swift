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

/// A server rejected a credential whose owner cannot recover automatically.
public struct TokenRejectedError: RequestCancellationError, Sendable {
  /// The rejecting response, with managed query credentials redacted.
  public let response: HTTPURLResponse

  /// Creates a terminal credential rejection.
  public init(response: HTTPURLResponse) { self.response = response }
}
