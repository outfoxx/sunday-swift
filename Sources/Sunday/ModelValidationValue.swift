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
import PotentCodables

/// A lazy, nonmutating field view shared by stored models and original wire values.
///
/// Object fields are inspected only after entering the containing validator's cycle guard.
/// Creating a view never serializes a model or constructs an application model.
public struct ModelValidationValue {

  /// Primitive wire shapes, including omitted fields and values that cannot be serialized.
  public enum Kind: Sendable {
    case omitted, null, boolean, string, number, array, object, invalid
  }

  /// The uncoerced shape of the represented value.
  public let kind: Kind
  /// Text for string values, including enum raw values.
  public let string: String?
  /// A boolean value, kept distinct from numeric zero and one.
  public let boolean: Bool?
  /// An exact finite decimal number.
  public let number: ModelValidationNumber?
  /// A fallback's identity survives even when its raw value resembles a recognized value.
  public let isUnknown: Bool
  /// The reason an invalid storage value cannot participate in a wire payload.
  public let failureReason: ModelValidationDiagnostic.Reason?
  private let elementsProvider: (() -> [ModelValidationValue])?
  private let fieldsProvider: (() -> [String: ModelValidationValue])?
  private let identity: AnyObject?
  private let projectedValidator: ((ModelMode, inout ModelValidationContext) -> Bool)?
  private let projectedSchemas: Set<ObjectIdentifier>

  private init(
    _ kind: Kind,
    string: String? = nil,
    boolean: Bool? = nil,
    number: ModelValidationNumber? = nil,
    isUnknown: Bool = false,
    failureReason: ModelValidationDiagnostic.Reason? = nil,
    elements: (() -> [ModelValidationValue])? = nil,
    fields: (() -> [String: ModelValidationValue])? = nil,
    identity: AnyObject? = nil,
    projectedValidator: ((ModelMode, inout ModelValidationContext) -> Bool)? = nil,
    schemas: [Any.Type] = []
  ) {
    self.kind = kind
    self.string = string
    self.boolean = boolean
    self.number = number
    self.isUnknown = isUnknown
    self.failureReason = failureReason
    self.elementsProvider = elements
    self.fieldsProvider = fields
    self.identity = identity
    self.projectedValidator = projectedValidator
    self.projectedSchemas = Set(schemas.map(ObjectIdentifier.init))
  }

  /// A property that does not participate in this payload.
  public static var omitted: Self { Self(.omitted) }
  /// An explicit wire null, distinct from an omitted property.
  public static var null: Self { Self(.null) }
  /// A storage value without a valid JSON representation.
  public static var invalid: Self { Self(.invalid, failureReason: .invalidValue) }

  /// Retains a string without numeric or boolean coercion.
  public static func string(_ value: String, isUnknown: Bool = false) -> Self {
    Self(.string, string: value, isUnknown: isUnknown)
  }

  /// Projects Foundation date storage using its declared wire format, without encoding a model.
  public static func string(_ value: Date, format: String) -> Self {
    let formatter = ISO8601DateFormatter()
    switch format.lowercased() {
    case "date", "full-date": formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
    case "time", "partial-time": formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
    case "datetime-only", "date-time-only":
      formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
    default: formatter.formatOptions = [.withInternetDateTime]
    }
    if !["date", "full-date"].contains(format.lowercased()) &&
      value.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) != 0 {
      formatter.formatOptions.insert(.withFractionalSeconds)
    }
    return .string(formatter.string(from: value))
  }

  /// Retains boolean identity without numeric conversion.
  public static func boolean(_ value: Bool) -> Self { Self(.boolean, boolean: value) }

  /// Normalizes a finite number without rounding its decimal description.
  public static func number(_ value: String) -> Self {
    guard let number = ModelValidationNumber(validating: value) else {
      return Self(.invalid, failureReason: .nonFiniteNumber)
    }
    return Self(.number, number: number)
  }

  /// Retains an exact number supplied by a decoding adapter.
  public static func number(_ value: ModelValidationNumber) -> Self { Self(.number, number: value) }

  /// Keeps collections lazy so projection does not traverse recursive object graphs.
  public static func array(_ elements: @escaping () -> [ModelValidationValue]) -> Self {
    Self(.array, elements: elements)
  }

  /// Keeps reference identity separate from field contents for per-invocation cycle detection.
  public static func object(
    identity: AnyObject? = nil,
    isUnknown: Bool = false,
    schemas: [Any.Type] = [],
    validate: ((ModelMode, inout ModelValidationContext) -> Bool)? = nil,
    fields: @escaping () -> [String: ModelValidationValue]
  ) -> Self {
    Self(.object, isUnknown: isUnknown, fields: fields, identity: identity,
         projectedValidator: validate, schemas: schemas)
  }

  /// Projects a preserved dynamic value without invoking a codec or an application initializer.
  public init(_ value: AnyValue) {
    switch value {
    case .nil: self = .null
    case .bool(let value): self = .boolean(value)
    case .string(let value): self = .string(value)
    case .array(let values): self = .array { values.map(Self.init) }
    case .dictionary(let values):
      guard values.keys.allSatisfy({ $0.stringValue != nil }) else { self = .invalid; return }
      self = .object { Dictionary(uniqueKeysWithValues: values.map { ($0.key.stringValue!, Self($0.value)) }) }
    case .float16, .float, .double, .decimal:
      guard let number = ModelValidationNumber(value: value) else {
        self = Self(.invalid, failureReason: .nonFiniteNumber)
        return
      }
      self = Self(.number, number: number)
    default:
      guard let number = ModelValidationNumber(value: value) else { self = .invalid; return }
      self = Self(.number, number: number)
    }
  }

  /// Captures wire shape and precision without invoking any application model decoder.
  public static func decode(from decoder: Decoder) throws -> Self {
    if let container = try? decoder.container(keyedBy: WireKey.self) {
      var fields: [String: Self] = [:]
      for key in container.allKeys {
        fields[key.stringValue] = try decode(from: container.superDecoder(forKey: key))
      }
      return .object { fields }
    }
    if var container = try? decoder.unkeyedContainer() {
      var elements: [Self] = []
      while !container.isAtEnd { elements.append(try decode(from: container.superDecoder())) }
      return .array { elements }
    }
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { return .null }
    if let value = try? container.decode(Bool.self) { return .boolean(value) }
    if let value = try? container.decode(String.self) { return .string(value) }
    return try .number(ModelValidationNumber(from: decoder))
  }

  /// The current collection elements; obtaining these does not inspect child object fields.
  public var elements: [ModelValidationValue]? { elementsProvider?() }
  /// The current object fields, preserving explicit nulls and omitted PATCH operations.
  public var fields: [String: ModelValidationValue]? { fieldsProvider?() }

  /// Runs a schema at this value's identity without rejecting ordinary shared references.
  public func validating(
    context: inout ModelValidationContext,
    _ check: (inout ModelValidationContext) -> Bool
  ) -> Bool {
    if let identity { return context.withObject(identity, check) }
    return check(&context)
  }

  /// Whether this view retains an application payload's concrete schema identity.
  public var hasProjectedSchema: Bool { !projectedSchemas.isEmpty }

  /// Checks the selected payload type without constructing it or inferring identity from its wire fields.
  public func represents(_ schema: Any.Type) -> Bool {
    projectedSchemas.contains(ObjectIdentifier(schema))
  }

  /// Preserves subtype validation only when it includes the requested schema's assertions.
  /// Independent overlapping schemas always run their own canonical validator, including during decoding.
  public func validateNested(
    _ mode: ModelMode,
    schema: Any.Type,
    context: inout ModelValidationContext,
    declared: (ModelValidationValue, ModelMode, inout ModelValidationContext) -> Bool
  ) -> Bool {
    if let projectedValidator, projectedSchemas.contains(ObjectIdentifier(schema)) {
      return !context.validatesNestedModels || projectedValidator(mode, &context)
    }
    return declared(self, mode, &context)
  }

  /// Compares serialized structure without serializing, hashing models, or following cycles indefinitely.
  public func equivalent(to other: Self) -> Bool {
    var ancestors: Set<IdentityPair> = []
    return equivalent(to: other, ancestors: &ancestors)
  }

  private func equivalent(to other: Self, ancestors: inout Set<IdentityPair>) -> Bool {
    guard kind == other.kind else { return false }
    var pair: IdentityPair?
    if let left = identity, let right = other.identity {
      pair = IdentityPair(left: ObjectIdentifier(left), right: ObjectIdentifier(right))
      guard ancestors.insert(pair!).inserted else { return false }
    }
    defer { if let pair { ancestors.remove(pair) } }
    switch kind {
    case .omitted, .null: return true
    case .invalid: return false
    case .boolean: return boolean == other.boolean
    case .string: return string == other.string
    case .number: return number == other.number
    case .array:
      let left = elements ?? [], right = other.elements ?? []
      return left.count == right.count && zip(left, right).allSatisfy {
        $0.equivalent(to: $1, ancestors: &ancestors)
      }
    case .object:
      let left = (fields ?? [:]).filter { $0.value.kind != .omitted }
      let right = (other.fields ?? [:]).filter { $0.value.kind != .omitted }
      guard left.keys.sorted() == right.keys.sorted() else { return false }
      return left.keys.sorted().allSatisfy { left[$0]!.equivalent(to: right[$0]!, ancestors: &ancestors) }
    }
  }

  private struct WireKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init(intValue: Int) { self.stringValue = String(intValue) }
  }

  private struct IdentityPair: Hashable {
    let left: ObjectIdentifier
    let right: ObjectIdentifier
  }
}
