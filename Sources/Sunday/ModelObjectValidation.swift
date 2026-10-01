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

/// An object's canonical wire contract, independent of its application storage representation.
public struct ModelObjectValidation {

  /// A nested canonical validator, sharing direction, diagnostics, and cycle state.
  public typealias Validator = (ModelValidationValue, ModelMode, inout ModelValidationContext) -> Bool

  /// A declared field and its effective inherited constraints.
  public struct Field {
    /// The original wire property name.
    public let name: String
    /// Whether omission violates the schema.
    public let required: Bool
    fileprivate let validator: Validator

    /// Describes field presence and delegates value checks to its canonical schema.
    public init(_ name: String, required: Bool = false, validate: @escaping Validator) {
      self.name = name
      self.required = required
      self.validator = validate
    }
  }

  /// An assertion applying to every matching wire name, including declared names.
  public struct Pattern {
    private let expression: NSRegularExpression?
    fileprivate let validator: Validator

    /// Compiles a wire-name expression and retains its canonical value validator.
    public init(_ pattern: String, validate: @escaping Validator) {
      self.expression = try? NSRegularExpression(pattern: pattern)
      self.validator = validate
    }

    fileprivate func matches(_ key: String) -> Bool {
      expression?.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }
  }

  private let fields: [Field]
  private let patterns: [Pattern]
  private let closed: Bool
  private let additional: Validator?

  /// Stores schema metadata and lazy references to named validators; no models are retained.
  public init(
    fields: [Field],
    patterns: [Pattern] = [],
    closed: Bool = false,
    additional: Validator? = nil
  ) {
    self.fields = fields
    self.patterns = patterns
    self.closed = closed
    self.additional = additional
  }

  /// Validates fields in declaration order, then dynamic keys in lexical order.
  public func isValid(
    _ value: ModelValidationValue,
    _ mode: ModelMode,
    context: inout ModelValidationContext
  ) -> Bool {
    guard value.kind == .object else { return context.reject(.invalidValue) }
    return value.validating(context: &context) { context in
      let values = value.fields ?? [:]
      // Declared values keep fallback identity; patterns also see fields discarded by storage.
      let supplied = (context.originalFields ?? [:]).merging(values) { _, stored in stored }
      let declaredValid = validateDeclared(values, mode, context: &context)
      if !declaredValid && !context.collectsDiagnostics { return false }
      let dynamicValid = validateDynamic(supplied, mode, context: &context)
      return declaredValid && dynamicValid
    }
  }

  private func validateDeclared(
    _ values: [String: ModelValidationValue],
    _ mode: ModelMode,
    context: inout ModelValidationContext
  ) -> Bool {
    var valid = true
    for field in fields {
      let stored = values[field.name] ?? .omitted
      let presence = context.presence(
        of: .property(field.name),
        inferred: stored.kind == .omitted ? .omitted : stored.kind == .null ? .null : .value
      )
      let fieldValue: ModelValidationValue = presence == .null ? .null : stored
      let fieldValid = context.at(.property(field.name)) { context in
        if presence == .omitted { return field.required ? context.reject(.required) : true }
        return field.validator(fieldValue, mode, &context)
      }
      if !fieldValid {
        valid = false
        if !context.collectsDiagnostics { return false }
      }
    }
    return valid
  }

  private func validateDynamic(
    _ values: [String: ModelValidationValue],
    _ mode: ModelMode,
    context: inout ModelValidationContext
  ) -> Bool {
    let declaredNames = Set(fields.map(\.name))
    var valid = true
    for key in values.keys.sorted() {
      let value = context.originalFields?[key] ?? values[key]!
      guard value.kind != .omitted else { continue }
      let matching = patterns.filter { $0.matches(key) }
      let keyValid = context.at(.property(key)) { context in
        if matching.isEmpty && !declaredNames.contains(key) {
          if closed { return context.reject(.additionalProperty) }
          return additional?(value, mode, &context) ?? true
        }
        var valid = true
        for pattern in matching where !pattern.validator(value, mode, &context) {
          valid = false
          if !context.collectsDiagnostics { return false }
        }
        return valid
      }
      if !keyValid {
        valid = false
        if !context.collectsDiagnostics { return false }
      }
    }
    return valid
  }
}
