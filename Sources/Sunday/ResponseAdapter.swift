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

/// Adapts each received HTTP response before validation, decoding, or retry decisions.
public protocol ResponseAdapter: Sendable {
  /// Receives the exact adapted request sent for this attempt.
  /// Native HTTP response metadata is adapted without consuming the response body.
  /// Throw RequestCancellationError to stop the operation without error translation.
  func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse
}
