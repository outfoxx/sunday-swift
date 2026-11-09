/*
 * Copyright 2021 Outfox, Inc.
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


/// Adapts an outbound request before it is executed by a transport.
public protocol RequestAdapter: Sendable {

  /// Returns a complete request ready to send. An adapter that consumes a body stream must replace it.
  /// Called once per attempt, starting from the prepared request, and once for request export.
  /// Throw RequestCancellationError to stop the logical operation without error translation.
  func adapt(request: URLRequest) async throws -> URLRequest

}
