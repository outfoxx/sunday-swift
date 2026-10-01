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

import PotentCodables

/// Per-invocation traversal state for generated validators and constructor/decoder adapters.
public struct ModelValidationContext {

  public typealias PathComponent = ModelValidationDiagnostic.PathComponent
  public typealias Reason = ModelValidationDiagnostic.Reason

  /// Wire presence retained before a decoder or constructor normalizes its field values.
  public enum Presence: Sendable {
    case omitted
    case null
    case value
  }

  /// Whether validators should continue after a failure to collect diagnostics.
  public let collectsDiagnostics: Bool
  /// Decoders validate each freshly decoded child before its parent validates containing restrictions.
  public let validatesNestedModels: Bool
  public private(set) var path: [PathComponent]
  /// Branch selected by a successful canonical union check for a constructor or decoder adapter.
  public private(set) var selectedAlternative: Int?
  public private(set) var diagnostics: [ModelValidationDiagnostic] = []
  private var ancestors: Set<ObjectIdentifier> = []
  private var objectProperties: [[PathComponent]: Set<String>] = [:]
  private var numbers: [[PathComponent]: ModelValidationNumber] = [:]
  private var numberCollections: [[PathComponent]: [ModelValidationNumber?]] = [:]
  private var wireValues: [[PathComponent]: ModelValidationValue] = [:]
  private var dynamicValues: [[PathComponent]: AnyValue] = [:]
  private let presence: [[PathComponent]: Presence]

  /// Creates fresh traversal state. Validity is never reused between invocations.
  public init(
    collectsDiagnostics: Bool = false,
    validatesNestedModels: Bool = true,
    path: [PathComponent] = [],
    presence: [[PathComponent]: Presence] = [:]
  ) {
    self.collectsDiagnostics = collectsDiagnostics
    self.validatesNestedModels = validatesNestedModels
    self.path = path
    self.presence = presence
  }

  /// Retains explicit nulls and wire paths before decoded optional storage loses that distinction.
  public static func decoding(
    _ decoder: Decoder,
    numericFields: [String] = [],
    dynamicFields: [String] = [],
    retainValues: Bool = false
  ) throws -> ModelValidationContext {
    let path: [PathComponent] = decoder.codingPath.map { key in
      key.intValue.map(PathComponent.index) ?? .property(key.stringValue)
    }
    let container = try decoder.container(keyedBy: WireKey.self)
    var presence: [[PathComponent]: Presence] = [:]
    for key in container.allKeys {
      presence[path + [.property(key.stringValue)]] = try container.decodeNil(forKey: key) ? .null : .value
    }
    var context = ModelValidationContext(
      collectsDiagnostics: true,
      validatesNestedModels: false,
      path: path,
      presence: presence
    )
    context.objectProperties[path] = Set(container.allKeys.map(\.stringValue))
    if retainValues { context.wireValues[path] = try ModelValidationValue.decode(from: decoder) }
    for name in dynamicFields {
      let key = WireKey(stringValue: name)
      guard container.contains(key) else { continue }
      let nested = try container.superDecoder(forKey: key)
      let scalar = try nested.singleValueContainer()
      // AnyValue's BigInt decoder accepts numeric strings. Preserve their wire identity
      // before that conversion so schema assertions cannot confuse "0" with 0.
      if let string = try? scalar.decode(String.self) {
        context.dynamicValues[path + [.property(name)]] = .string(string)
      }
      else {
        context.dynamicValues[path + [.property(name)]] = try AnyValue(from: nested)
      }
    }
    for name in numericFields {
      let key = WireKey(stringValue: name)
      guard container.contains(key), try !container.decodeNil(forKey: key) else { continue }
      let nested = try container.superDecoder(forKey: key)
      let fieldPath = path + [.property(name)]
      if var array = try? nested.unkeyedContainer() {
        var values: [ModelValidationNumber?] = []
        while !array.isAtEnd {
          values.append(try array.decodeIfPresent(ModelValidationNumber.self))
        }
        context.numberCollections[fieldPath] = values
      }
      else {
        context.numbers[fieldPath] = try ModelValidationNumber(from: nested)
      }
    }
    return context
  }

  /// Captures a scalar or union's wire value before primitive storage can round its numeric representation.
  public static func decodingValue(_ decoder: Decoder) throws -> ModelValidationContext {
    let path: [PathComponent] = decoder.codingPath.map { key in
      key.intValue.map(PathComponent.index) ?? .property(key.stringValue)
    }
    var context = ModelValidationContext(collectsDiagnostics: true, validatesNestedModels: false, path: path)
    context.wireValues[path] = try ModelValidationValue.decode(from: decoder)
    return context
  }

  /// Tests a union alternative without leaking a rejected alternative's diagnostics or traversal state.
  public func matches(_ validate: (inout ModelValidationContext) -> Bool) -> Bool {
    var probe = ModelValidationContext(
      validatesNestedModels: validatesNestedModels, path: path, presence: presence
    )
    probe.ancestors = ancestors
    probe.objectProperties = objectProperties
    probe.numbers = numbers
    probe.numberCollections = numberCollections
    probe.dynamicValues = dynamicValues
    probe.wireValues = wireValues
    return validate(&probe)
  }

  /// Retains a successful branch choice so construction does not need to repeat schema predicates.
  public mutating func selectAlternative(_ index: Int) {
    selectedAlternative = index
  }

  /// Original object keys, retained before unknown properties can be discarded during decoding.
  public var propertyNames: Set<String>? { objectProperties[path] }

  /// Original wire value at the current path, including values within retained dynamic containers.
  public var originalValue: ModelValidationValue? {
    guard let prefix = wireValues.keys.filter({ path.starts(with: $0) }).max(by: { $0.count < $1.count }) else {
      return nil
    }
    var value = wireValues[prefix]
    for component in path.dropFirst(prefix.count) {
      switch component {
      case .property(let name), .key(let name): value = value?.fields?[name]
      case .index(let index):
        guard let elements = value?.elements, elements.indices.contains(index) else { return nil }
        value = elements[index]
      }
    }
    return value
  }

  /// Original dynamic fields retained before optional unknown-field discarding.
  public var originalFields: [String: ModelValidationValue]? { originalValue?.fields }

  /// Exact input at this wire path, when supplied by a decoding adapter.
  public var number: ModelValidationNumber? { numbers[path] }

  /// Original dynamic scalar identity, retained before a permissive parser can coerce it.
  public var dynamicValue: AnyValue? { dynamicValues[path] }

  /// Original numeric elements, before collection conversion can reorder or remove elements.
  public var numberElements: [ModelValidationNumber?]? { numberCollections[path] }

  /// Uses retained wire presence when available, otherwise the model's storage semantics.
  public func presence(of component: PathComponent, inferred: Presence) -> Presence {
    if let captured = presence[path + [component]] { return captured }
    if case .property(let name) = component, let names = propertyNames, !names.contains(name) {
      return .omitted
    }
    return inferred
  }

  /// Records a failure at the current wire path and returns false for Boolean composition.
  @discardableResult
  public mutating func reject(_ reason: Reason) -> Bool {
    if collectsDiagnostics {
      diagnostics.append(ModelValidationDiagnostic(path: path, reason: reason))
    }
    return false
  }

  /// Describes this invocation's failures, including an unclassified failure from a custom validator.
  public var validationError: ModelValidationError {
    ModelValidationError(diagnostics: diagnostics.isEmpty
      ? [ModelValidationDiagnostic(path: path, reason: .invalidValue)]
      : diagnostics)
  }

  /// Translates schema diagnostics to Codable's error contract without validating again.
  public var decodingError: DecodingError {
    let error = validationError
    let codingPath: [any CodingKey] = (error.diagnostics.first?.path ?? path).map { component in
      switch component {
      case .index(let index): WireKey(intValue: index)
      case .property(let name), .key(let name): WireKey(stringValue: name)
      }
    }
    return .dataCorrupted(.init(
      codingPath: codingPath,
      debugDescription: error.errorDescription ?? "Invalid model",
      underlyingError: error
    ))
  }

  /// Evaluates a nested validator at its wire path and restores the containing path afterward.
  public mutating func at(
    _ component: PathComponent,
    _ validate: (inout ModelValidationContext) -> Bool
  ) -> Bool {
    path.append(component)
    defer { path.removeLast() }
    return validate(&self)
  }

  /// Protects recursive reference models while allowing the same child on separate branches.
  public mutating func withObject(
    _ value: AnyObject,
    _ validate: (inout ModelValidationContext) -> Bool
  ) -> Bool {
    let identity = ObjectIdentifier(value)
    guard ancestors.insert(identity).inserted else { return reject(.cycle) }
    defer { ancestors.remove(identity) }
    return validate(&self)
  }
  private struct WireKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
      self.stringValue = stringValue
      self.intValue = nil
    }
    init(intValue: Int) {
      self.stringValue = String(intValue)
      self.intValue = intValue
    }
  }
}
