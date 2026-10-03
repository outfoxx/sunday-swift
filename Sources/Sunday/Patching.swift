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


/// JSON Merge Patch Operation
///
public protocol AnyPatchOp: Codable, Sendable {
  /// The non-optional value supplied by a set or merge operation.
  associatedtype Value: Codable & Sendable

  /// Whether this operation leaves its containing member untouched.
  var isUnchanged: Bool { get }

  /// Creates a set or merge operation.
  static func merge(_ value: Value) -> Self
}


// MARK: UpdateOp

/// Wrapper that represents a limited patch operation supporting setting/merging, or not changing the target property in
/// the target object. The delete operation is **not** supported by ``UpdateOp``.
///
/// Use a non-optional `Value`. Omitted members decode as ``unchanged``.
///
/// - SeeAlso ``PatchOp``
///
public enum UpdateOp<Value: Codable & Sendable>: AnyPatchOp, Codable {

  /// Leave the target property unchanged.
  case unchanged

  /// Set/Merge the target property in the target object.
  ///
  /// If the patch is a primitive (e.g. string, boolean or number) or an array, the
  /// target value will be replaced with the patch value. Objects will be merged with
  /// the target value in the target object.
  ///
  case set(Value)

  /// Whether this operation leaves its containing member untouched.
  public var isUnchanged: Bool {
    if case .unchanged = self { return true }
    return false
  }

  /// Calls the block only when the operation supplies a value.
  ///
  /// - ``set(_:)``
  ///   Set calls the block with the new value.
  ///
  public func use(block: (Value) throws -> Void) rethrows {
    switch self {
    case .unchanged: break
    case .set(let value):
      try block(value)
    }
  }

  /// Returns the supplied value, or nil when unchanged.
  ///
  /// - ``set(_:)``
  ///   Set returns the provided value.
  ///
  public func get() -> Value? {
    switch self {
    case .unchanged: return nil
    case .set(let value): return value
    }
  }

  // MARK: Codable Conformance

  /// Decodes a present operation; omission is handled by the keyed container.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard !container.decodeNil() else {
      throw DecodingError.valueNotFound(Value.self, .init(
        codingPath: decoder.codingPath, debugDescription: "UpdateOp does not support deletion (JSON null)"
      ))
    }
    self = .set(try container.decode(Value.self))
  }

  /// Encodes a present operation. Unchanged has no standalone JSON representation.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .unchanged:
      throw EncodingError.invalidValue(self, .init(
        codingPath: encoder.codingPath,
        debugDescription: "An unchanged operation must be omitted from its containing object"
      ))
    case .set(value: let value):
      if case Optional<Any>.none = value as Any {
        throw EncodingError.invalidValue(value, .init(
          codingPath: encoder.codingPath, debugDescription: "A set operation cannot encode null; use PatchOp.delete"
        ))
      }
      try container.encode(value)
    }
  }

}


// MARK: PatchOp

/// A full patch operation supporting setting/merging, deleting or leaving the target property unchanged.
///
/// Use a non-optional `Value`. Omitted members decode as ``unchanged``.
/// - SeeAlso ``UpdateOp``
///
public enum PatchOp<Value: Codable & Sendable>: AnyPatchOp, Codable {

  /// Leave the target property unchanged.
  case unchanged

  /// Set/Merge the target property in the target object.
  ///
  /// If the patch is a primitive (e.g. string, boolean or number) or an array, the
  /// target value will be replaced with the patch value. Objects will be merged with
  /// the target value in the target object.
  ///
  case set(Value)

  /// Delete the target property in the target object.
  ///
  case delete

  /// Whether this operation leaves its containing member untouched.
  public var isUnchanged: Bool {
    if case .unchanged = self { return true }
    return false
  }

  /// Calls the block for a set or delete operation; unchanged operations do not call it.
  ///
  /// - ``set(_:)``
  ///   Set calls the block with the new value.
  /// - ``delete``
  ///   Delete call the block with nil.
  ///
  public func use(block: (Value?) throws -> Void) rethrows {
    switch self {
    case .unchanged: break
    case .set(let value):
      try block(value)
    case .delete:
      try block(nil)
    }
  }

  /// Returns the supplied or deletion value, or nil when unchanged.
  ///
  /// - ``set(_:)``
  ///   Set returns the provided value.
  /// - ``delete``
  ///   Delete returns the result of the deleted closure.
  ///
  public func get(deleted: @autoclosure () -> Value) -> Value? {
    switch self {
    case .unchanged: return nil
    case .set(let value): return value
    case .delete: return deleted()
    }
  }

  // MARK: Codable Conformance

  /// Decodes a present operation; omission is handled by the keyed container.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .delete
    }
    else {
      self = .set(try container.decode(Value.self))
    }
  }

  /// Encodes a present operation. Unchanged has no standalone JSON representation.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .unchanged:
      throw EncodingError.invalidValue(self, .init(
        codingPath: encoder.codingPath,
        debugDescription: "An unchanged operation must be omitted from its containing object"
      ))
    case .set(value: let value):
      if case Optional<Any>.none = value as Any {
        throw EncodingError.invalidValue(value, .init(
          codingPath: encoder.codingPath, debugDescription: "A set operation cannot encode null; use PatchOp.delete"
        ))
      }
      try container.encode(value)
    case .delete:
      try container.encodeNil()
    }
  }

}


// MARK: UpdateOp Conformances

extension UpdateOp {

  /// Creates an operation that sets or merges the supplied value.
  public static func merge<NewValue: Codable & Sendable>(_ value: NewValue) -> UpdateOp<NewValue> { .set(value) }

}

extension UpdateOp: Equatable where Value: Equatable {}

extension UpdateOp: CustomStringConvertible {

  /// A description preserving the operation state.
  public var description: String {
    switch self {
    case .unchanged: return "unchanged"
    case .set(let value): return "set(\(value))"
    }
  }

}


// MARK: PatchOp Conformances

extension PatchOp {

  /// Creates an operation that sets or merges the supplied value.
  public static func merge<NewValue: Codable & Sendable>(_ value: NewValue) -> PatchOp<NewValue> { .set(value) }

}

extension PatchOp: Equatable where Value: Equatable {}

extension PatchOp: CustomStringConvertible {

  /// A description preserving the operation state.
  public var description: String {
    switch self {
    case .unchanged: return "unchanged"
    case .set(let value): return "set(\(value))"
    case .delete: return "delete"
    }
  }

}


// MARK: KeyedDecodingContainer Extensions

extension KeyedDecodingContainer {

  /// Decodes a non-optional update field, leaving an omitted member unchanged.
  public func decode<Value>(_ type: UpdateOp<Value>.Type, forKey key: Key) throws -> UpdateOp<Value> {
    guard contains(key) else { return .unchanged }
    return try UpdateOp(from: superDecoder(forKey: key))
  }

  /// Decodes a non-optional patch field, preserving omission and explicit deletion.
  public func decode<Value>(_ type: PatchOp<Value>.Type, forKey key: Key) throws -> PatchOp<Value> {
    guard contains(key) else { return .unchanged }
    return try PatchOp(from: superDecoder(forKey: key))
  }

  /// Decodes a patch field, preserving omission as `nil` and explicit null as `.delete`.
  public func decodeIfExists<Value: Codable & Sendable>(_ type: Value.Type, forKey key: Key) throws -> PatchOp<Value>? {
    guard contains(key) else {
      return nil
    }
    return try decodeIfPresent(type, forKey: key).map { .set($0) } ?? .delete
  }

  /// Decodes an update field, preserving omission as `nil` and validating every present value.
  ///
  /// Explicit null always fails; an update cannot delete its target member.
  public func decodeIfExists<Value: Codable & Sendable>(
    _ type: Value.Type,
    forKey key: Key
  ) throws -> UpdateOp<Value>? {
    guard contains(key) else {
      return nil
    }
    return try decode(UpdateOp<Value>.self, forKey: key)
  }

}


// MARK: KeyedEncodingContainer Extensions

extension KeyedEncodingContainer {

  /// Omits an unchanged update field, including with synthesized Codable conformance.
  public mutating func encode<Value>(_ value: UpdateOp<Value>, forKey key: Key) throws {
    guard !value.isUnchanged else { return }
    try value.encode(to: superEncoder(forKey: key))
  }

  /// Omits an unchanged patch field, including with synthesized Codable conformance.
  public mutating func encode<Value>(_ value: PatchOp<Value>, forKey key: Key) throws {
    guard !value.isUnchanged else { return }
    try value.encode(to: superEncoder(forKey: key))
  }

  /// Encodes a present legacy optional operation while omitting nil and unchanged states.

  public mutating func encodeIfExists<Value: Sendable, P: AnyPatchOp>(
    _ value: P?,
    forKey key: Key
  ) throws where P.Value == Value {
    guard let value = value, !value.isUnchanged else {
      return
    }
    return try encodeIfPresent(value, forKey: key)
  }

}


// MARK: MediaType Extensions

public extension MediaType {

  /// JSON Patch media type.
  static let jsonPatch = MediaType(type: .application, tree: .standard, subtype: "json-patch", suffix: .json)
  /// JSON Merge Patch media type.
  static let mergePatch = MediaType(type: .application, tree: .standard, subtype: "merge-patch", suffix: .json)

}
