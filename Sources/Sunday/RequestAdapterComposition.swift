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

/// Explicitly composes request adapters in order. Errors stop the remaining adapters.
public struct RequestAdapters: RequestAdapter {
  fileprivate let adapters: [any RequestAdapter]

  /// Creates a chain that passes each adapter's output to the next adapter.
  public init(_ adapters: any RequestAdapter...) { self.adapters = adapters.flatMap { $0.unroll() } }

  /// Creates a chain from an ordered array of adapters.
  public init(_ adapters: [any RequestAdapter]) { self.adapters = adapters.flatMap { $0.unroll() } }

  /// Adapts using the configured order without acquiring any additional lifecycle behavior.
  public func adapt(request: URLRequest) async throws -> URLRequest {
    var result = request
    for adapter in adapters {
      result = try await adaptRequest(result, using: adapter)
    }
    return result
  }
}

public extension RequestAdapter {
  /// Appends an adapter, flattening existing compositions while preserving execution order.
  func chain(to next: any RequestAdapter) -> some RequestAdapter {
    RequestAdapters(unroll() + next.unroll())
  }
}

private extension RequestAdapter {
  func unroll() -> [any RequestAdapter] {
    (self as? RequestAdapters)?.adapters ?? [self]
  }
}
