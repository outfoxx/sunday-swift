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
import PotentCodables
import PotentJSON

/// RFC 9457 decoding confined to the five standard members at the current object level.
public enum ProblemDecoding {
  /// Returns a view with null and wrong-category standard members absent. Child decoders are unchanged.
  public static func normalized(_ decoder: Decoder) throws -> Decoder {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    var ignored = Set<String>()
    for name in ["type", "title", "status", "detail", "instance"] {
      let key = AnyCodingKey(stringValue: name)
      guard container.contains(key) else { continue }
      // AnyValue may interpret numeric strings as BigInt; inspect strings and
      // booleans first so their JSON categories cannot be lost to that conversion.
      do {
        let string = try container.decode(String.self, forKey: key)
        try validateReference(string, forKey: key, in: container)
        if name == "status" { ignored.insert(name) }
        continue
      }
      catch DecodingError.typeMismatch {
        // Continue checking the original JSON category.
      }
      catch DecodingError.valueNotFound {
        ignored.insert(name)
        continue
      }
      do {
        _ = try container.decode(Bool.self, forKey: key)
        ignored.insert(name)
        continue
      }
      catch DecodingError.typeMismatch {
        // Continue checking the original JSON category.
      }
      catch DecodingError.valueNotFound {
        ignored.insert(name)
        continue
      }
      let value = try container.decode(AnyValue.self, forKey: key)
      if name == "status" {
        switch value {
        case .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64,
             .integer, .unsignedInteger, .float16, .float, .double, .decimal:
          // Numeric category is valid; fractional or out-of-range values remain errors.
          try validateIntegralStatus(forKey: key, in: container)
        default: ignored.insert(name)
        }
      }
      else if value.stringValue == nil { ignored.insert(name) }
    }
    return NormalizedDecoder(base: decoder, ignored: ignored)
  }

  private static func validateIntegralStatus(forKey key: AnyCodingKey,
                                             in container: KeyedDecodingContainer<AnyCodingKey>) throws {
    let decimal = try container.decode(Decimal.self, forKey: key)
    var input = decimal
    var rounded = Decimal()
    NSDecimalRound(&rounded, &input, 0, .plain)
    guard rounded == decimal else {
      throw DecodingError.dataCorruptedError(forKey: key, in: container,
        debugDescription: "Problem status must be an integer")
    }
  }

  private static func validateReference(_ value: String, forKey key: AnyCodingKey,
                                        in container: KeyedDecodingContainer<AnyCodingKey>) throws {
    guard ["type", "instance"].contains(key.stringValue), !value.isEmpty else { return }
    guard URL(string: value) != nil else {
      throw DecodingError.dataCorruptedError(forKey: key, in: container,
        debugDescription: "Invalid Problem URI reference")
    }
  }

  // A JSON tree retains numeric lexemes in extensions while applying HTTP defaults
  // before the application's configured decoder constructs a registered subtype.
  static func contextualJSON(_ data: Data, status: Int) throws -> (Data, String) {
    guard case .object(var fields) = try PotentJSON.JSONSerialization.json(from: data) else {
      throw DecodingError.typeMismatch([String: AnyValue].self,
        .init(codingPath: [], debugDescription: "Expected a Problem object"))
    }
    for key in ["type", "title", "status", "detail", "instance"] {
      guard let value = fields[key] else { continue }
      switch (key, value) {
      case ("status", .number): break
      case ("status", _): fields.removeValue(forKey: key)
      case (_, .string): break
      default: fields.removeValue(forKey: key)
      }
    }
    if let bodyStatus = fields["status"] {
      // Validate before a generic dictionary can round a near-integer JSON number to Double.
      var value = try PotentJSON.JSONDecoder().decodeTree(Decimal.self, from: bodyStatus)
      var rounded = Decimal()
      NSDecimalRound(&rounded, &value, 0, .plain)
      guard value == rounded else {
        throw DecodingError.dataCorrupted(.init(codingPath: [AnyCodingKey("status")],
          debugDescription: "Problem status must be an integer"))
      }
    }
    let type = fields["type"]?.stringValue ?? "about:blank"
    fields["type"] = .string(type)
    if fields["status"] == nil { fields["status"] = .number(.init(status)) }
    if type == "about:blank", fields["title"] == nil, let bodyStatus = fields["status"] {
      let effective = try PotentJSON.JSONDecoder().decodeTree(Int.self, from: bodyStatus)
      fields["title"] = .string(GenericProblem.statusTitle(statusCode: effective))
    }
    return (try PotentJSON.JSONSerialization.data(from: .object(fields)), type)
  }

  private struct NormalizedDecoder: Decoder {
    let base: Decoder
    let ignored: Set<String>
    var codingPath: [CodingKey] { base.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
      let container = try base.container(keyedBy: type)
      let typeKey = Key(stringValue: "type")
      let defaultType = typeKey.map { ignored.contains("type") || !container.contains($0) } ?? false
      return KeyedDecodingContainer(Container(base: container, ignored: ignored,
        defaultType: defaultType, userInfo: userInfo))
    }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { try base.unkeyedContainer() }
    func singleValueContainer() throws -> SingleValueDecodingContainer { try base.singleValueContainer() }
  }

  private struct Container<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let base: KeyedDecodingContainer<Key>
    let ignored: Set<String>
    let defaultType: Bool
    let userInfo: [CodingUserInfoKey: Any]
    var codingPath: [CodingKey] { base.codingPath }
    var allKeys: [Key] {
      var keys = base.allKeys.filter { !ignored.contains($0.stringValue) }
      if defaultType, let key = Key(stringValue: "type"), !keys.contains(where: { $0.stringValue == "type" }) {
        keys.append(key)
      }
      return keys
    }
    func isDefaultType(_ key: Key) -> Bool { defaultType && key.stringValue == "type" }
    func contains(_ key: Key) -> Bool {
      isDefaultType(key) || (!ignored.contains(key.stringValue) && base.contains(key))
    }
    func require(_ key: Key) throws {
      guard contains(key) else {
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing Problem member"))
      }
    }
    func decodeNil(forKey key: Key) throws -> Bool {
      if isDefaultType(key) { return false }
      try require(key)
      return try base.decodeNil(forKey: key)
    }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
      if isDefaultType(key) { return "about:blank" }
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
      if isDefaultType(key) {
        return try T(from: defaultDecoder(key))
      }
      try require(key)
      return try base.decode(type, forKey: key)
    }
    func nestedContainer<N: CodingKey>(keyedBy type: N.Type, forKey key: Key) throws -> KeyedDecodingContainer<N> {
      try require(key)
      return try base.nestedContainer(keyedBy: type, forKey: key)
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
      try require(key)
      return try base.nestedUnkeyedContainer(forKey: key)
    }
    func superDecoder() throws -> Decoder { try base.superDecoder() }
    func defaultDecoder(_ key: Key) -> Decoder {
      DefaultTypeDecoder(codingPath: codingPath + [key], userInfo: userInfo)
    }
    func superDecoder(forKey key: Key) throws -> Decoder {
      if isDefaultType(key) { return defaultDecoder(key) }
      try require(key)
      return try base.superDecoder(forKey: key)
    }
  }

  // Only the synthetic RFC default uses this decoder; real values keep the configured decoder.
  private struct DefaultTypeDecoder: Decoder, SingleValueDecodingContainer {
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    func mismatch<T>(_ type: T.Type) -> DecodingError {
      .typeMismatch(type, .init(codingPath: codingPath, debugDescription: "Expected a string"))
    }
    func container<Key: CodingKey>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
      throw mismatch([String: String].self)
    }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { throw mismatch([String].self) }
    func singleValueContainer() throws -> SingleValueDecodingContainer { self }
    func decodeNil() -> Bool { false }
    func decode(_: String.Type) -> String { "about:blank" }
    func decode(_ type: Bool.Type) throws -> Bool { throw mismatch(type) }
    func decode(_ type: Double.Type) throws -> Double { throw mismatch(type) }
    func decode(_ type: Float.Type) throws -> Float { throw mismatch(type) }
    func decode(_ type: Int.Type) throws -> Int { throw mismatch(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { throw mismatch(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { throw mismatch(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { throw mismatch(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { throw mismatch(type) }
    func decode(_ type: UInt.Type) throws -> UInt { throw mismatch(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { throw mismatch(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { throw mismatch(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { throw mismatch(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { throw mismatch(type) }
    func decode<T: Decodable>(_: T.Type) throws -> T { try T(from: self) }
  }

}
