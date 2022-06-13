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
public protocol AnyPatchOp: Codable {
  associatedtype Value: Codable

  static func merge(_ value: Value) -> Self
}


// MARK: UpdateOp

/// Wrapper that represents a limited patch operation support seting/merging, not changing the target property in the
/// target object. Thedelete operation is **not** supported by ``UpdateOp``.
///
/// - Note A "no change" operation is represented by the ``nil`` value.
///
/// - SeeAlso ``PatchOp``
///
public enum UpdateOp<Value: Codable>: AnyPatchOp, Codable {

  /// Set/Merge the target property in the target object.
  ///
  /// If the patch is a primitive (e.g. string, boolean or number) or an array, the
  /// target value will be replaced with the patch value. Objects will be merged with
  /// the target value in the target object.
  ///
  case set(Value)

  /// Call a provided block with with a value translated from the patch operator.
  ///
  /// - ``set(_:)``
  ///   Set calls the block with the new value.
  ///
  public func use(block: (Value) throws -> Void) rethrows {
    switch self {
    case .set(let value):
      try block(value)
    }
  }

  /// Provies a value translated from the patch operator
  ///
  /// - ``set(_:)`
  ///   Set returns the provided value.
  ///
  public func get() -> Value {
    switch self {
    case .set(let value): return value
    }
  }

  // MARK: Codable Conformance

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = .set(try container.decode(Value.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .set(value: let value):
      try container.encode(value)
    }
  }

}


// MARK: PatchOp

/// A full patch operation support seting/merging, deleting or not changing the target property in the target object.
///
/// - Note A "no change" operation is represented by the ``nil`` value.
/// - SeeAlso ``UpdateOp``
///
public enum PatchOp<Value: Codable>: AnyPatchOp, Codable {

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

  /// Call a provided block with with a value translated from the patch operator.
  ///
  /// - ``set(_:)``
  ///   Set calls the block with the new value.
  /// - ``delete``
  ///   Delete call the block with nil.
  ///
  public func use(block: (Value?) throws -> Void) rethrows {
    switch self {
    case .set(let value):
      try block(value)
    case .delete:
      try block(nil)
    }
  }

  /// Provies a value translated from the patch operator and lambdas
  ///
  /// - ``set(_:)`
  ///   Set returns the provided value.
  /// - ``delete``
  ///   Delete returns the result of the deleted closure.
  ///
  public func get(deleted: @autoclosure () -> Value) -> Value {
    switch self {
    case .set(let value): return value
    case .delete: return deleted()
    }
  }

  // MARK: Codable Conformance

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .delete
    }
    else {
      self = .set(try container.decode(Value.self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .set(value: let value):
      try container.encode(value)
    case .delete:
      try container.encodeNil()
    }
  }

}


// MARK: UpdateOp Conformances

extension UpdateOp {

  public static func merge<Value: Codable>(_ value: Value) -> UpdateOp<Value> { .set(value) }

}

extension UpdateOp: Equatable where Value: Equatable {}

extension UpdateOp: CustomStringConvertible {

  public var description: String {
    switch self {
    case .set(let value): return "set(\(value))"
    }
  }

}


// MARK: PatchOp Conformances

extension PatchOp {

  public static func merge<Value: Codable>(_ value: Value) -> PatchOp<Value> { .set(value) }

}

extension PatchOp: Equatable where Value: Equatable {}

extension PatchOp: CustomStringConvertible {

  public var description: String {
    switch self {
    case .set(let value): return "set(\(value))"
    case .delete: return "delete"
    }
  }

}


// MARK: KeyedDecodingContainer Extensions

extension KeyedDecodingContainer {

  public func decodeIfExists<Value: Codable>(_ type: Value.Type, forKey key: Key) throws -> PatchOp<Value>? {
    guard contains(key) else {
      return nil
    }
    return try decodeIfPresent(type, forKey: key).map { .set($0) } ?? .delete
  }

  public func decodeIfExists<Value: Codable>(_ type: Value.Type, forKey key: Key) throws -> UpdateOp<Value>? {
    return try decodeIfPresent(type, forKey: key).map { .set($0) }
  }

}


// MARK: KeyedEncodingContainer Extensions

extension KeyedEncodingContainer {

  public mutating func encodeIfExists<Value, P: AnyPatchOp>(
    _ value: P?,
    forKey key: Key
  ) throws where P.Value == Value {
    guard let value = value else {
      return
    }
    return try encodeIfPresent(value, forKey: key)
  }

}


// MARK: MediaType Extensions

extension MediaType {

  static let jsonPatch = MediaType(type: .application, tree: .standard, subtype: "json-patch", suffix: .json)
  static let mergePatch = MediaType(type: .application, tree: .standard, subtype: "merge-patch", suffix: .json)

}
