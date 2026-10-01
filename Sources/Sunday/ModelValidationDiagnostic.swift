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

/// A schema validation failure identified by a stable reason and its wire path.
public struct ModelValidationDiagnostic: Equatable, Sendable {

  /// One step in a path through the serialized payload.
  public enum PathComponent: Hashable, Sendable {
    case property(String)
    case index(Int)
    case key(String)

    /// The JSON Pointer spelling of this component, before escaping.
    public var value: String {
      switch self {
      case .property(let name), .key(let name): return name
      case .index(let index): return String(index)
      }
    }
  }

  /// Stable reason codes shared by generated validators and their adapters.
  public enum Reason: String, Sendable {
    case required
    case nullValue = "null_value"
    case allowedValue = "allowed_value"
    case minimum
    case maximum
    case multipleOf = "multiple_of"
    case minLength = "min_length"
    case maxLength = "max_length"
    case pattern
    case minItems = "min_items"
    case maxItems = "max_items"
    case uniqueItems = "unique_items"
    case additionalProperty = "additional_property"
    case discriminator
    case unknownEnum = "unknown_enum"
    case unknownUnion = "unknown_union"
    case nonFiniteNumber = "non_finite_number"
    case cycle
    case invalidValue = "invalid_value"
  }

  public let path: [PathComponent]
  public let reason: Reason

  /// Creates a diagnostic without retaining potentially sensitive application values.
  public init(path: [PathComponent], reason: Reason) {
    self.path = path
    self.reason = reason
  }

  /// The RFC 6901 JSON Pointer for this failure; an empty string denotes the root.
  public var jsonPointer: String {
    path.map { "/" + $0.value.replacingOccurrences(of: "~", with: "~0")
      .replacingOccurrences(of: "/", with: "~1") }.joined()
  }
}
