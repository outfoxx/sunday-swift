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

/// Explicitly composes response adapters in order. Errors stop the remaining adapters.
public struct ResponseAdapters: ResponseAdapter {
  fileprivate let adapters: [any ResponseAdapter]

  /// Creates a chain that passes each adapter's output to the next adapter.
  public init(_ adapters: any ResponseAdapter...) { self.adapters = adapters.flatMap { $0.unroll() } }

  /// Creates a chain from an ordered array of adapters.
  public init(_ adapters: [any ResponseAdapter]) { self.adapters = adapters.flatMap { $0.unroll() } }

  /// Adapts using the configured order without acquiring any additional lifecycle behavior.
  public func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
    var result = response
    for adapter in adapters {
      try Task.checkCancellation()
      result = try await adapter.adapt(response: result, for: request)
    }
    try Task.checkCancellation()
    return result
  }
}

public extension ResponseAdapter {
  /// Appends an adapter, flattening existing compositions while preserving execution order.
  func chain(to next: any ResponseAdapter) -> some ResponseAdapter {
    ResponseAdapters(unroll() + next.unroll())
  }
}

private extension ResponseAdapter {
  func unroll() -> [any ResponseAdapter] {
    (self as? ResponseAdapters)?.adapters ?? [self]
  }
}
