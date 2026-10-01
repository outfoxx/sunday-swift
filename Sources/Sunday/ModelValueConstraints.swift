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

/// Schema assertions evaluated identically for typed fields and preserved dynamic values.
public struct ModelValueConstraints {

  /// An assertion and its immutable schema metadata, in deterministic diagnostic order.
  public enum Rule {
    case allowedValues([ModelValidationValue])
    case minLength(Int)
    case maxLength(Int)
    case pattern(String)
    case minimum(ModelValidationNumber, exclusive: Bool = false)
    case maximum(ModelValidationNumber, exclusive: Bool = false)
    case multipleOf(digits: [Int], exponent: Int)
    case minItems(Int)
    case maxItems(Int)
    case uniqueItems
    case elements(ModelValueConstraints, nullable: Bool)
  }

  private let rules: [Rule]

  /// Creates reusable schema metadata; no application values or validation results are retained.
  public init(_ rules: [Rule]) { self.rules = rules }

  /// Adds a rule while preserving schema declaration order.
  public func appending(_ rule: Rule) -> Self { Self(rules + [rule]) }

  /// Checks current values once, stopping early unless the caller requests diagnostics.
  public func isValid(_ value: ModelValidationValue, context: inout ModelValidationContext) -> Bool {
    let value = context.originalValue ?? context.number.map(ModelValidationValue.number) ?? value
    guard value.kind != .invalid else { return context.reject(value.failureReason ?? .invalidValue) }
    var valid = true
    for rule in rules {
      let failure: ModelValidationDiagnostic.Reason?
      switch rule {
      case .allowedValues(let values):
        failure = values.contains(where: { value.equivalent(to: $0) }) ? nil : .allowedValue
      case .minLength(let bound):
        failure = value.string.map { $0.unicodeScalars.count >= bound } == true ? nil : .minLength
      case .maxLength(let bound):
        failure = value.string.map { $0.unicodeScalars.count <= bound } == true ? nil : .maxLength
      case .pattern(let pattern):
        if let string = value.string, let expression = try? NSRegularExpression(pattern: pattern) {
          // String.range cannot represent a match ending inside an extended grapheme cluster.
          failure = expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
            ? nil : .pattern
        }
        else {
          failure = .pattern
        }
      case .minimum(let bound, let exclusive):
        failure = value.number.map { exclusive ? $0 > bound : $0 >= bound } == true ? nil : .minimum
      case .maximum(let bound, let exclusive):
        failure = value.number.map { exclusive ? $0 < bound : $0 <= bound } == true ? nil : .maximum
      case .multipleOf(let digits, let exponent):
        failure = value.number?.isMultipleOf(digits: digits, exponent: exponent) == true ? nil : .multipleOf
      case .minItems(let bound):
        failure = value.elements.map { $0.count >= bound } == true ? nil : .minItems
      case .maxItems(let bound):
        failure = value.elements.map { $0.count <= bound } == true ? nil : .maxItems
      case .elements(let constraints, let nullable):
        guard let elements = value.elements else { return context.reject(.invalidValue) }
        for (index, element) in elements.enumerated() where !nullable || element.kind != .null {
          if !context.at(.index(index), { context in constraints.isValid(element, context: &context) }) {
            valid = false
            if !context.collectsDiagnostics { return false }
          }
        }
        failure = nil
      case .uniqueItems:
        failure = value.elements.map(Self.hasDuplicates) == false ? nil : .uniqueItems
      }
      if let failure {
        valid = context.reject(failure)
        if !context.collectsDiagnostics { return false }
      }
    }
    return valid
  }

  private static func hasDuplicates(_ elements: [ModelValidationValue]) -> Bool {
    elements.indices.contains { index in
      elements[..<index].contains { $0.equivalent(to: elements[index]) }
    }
  }
}
