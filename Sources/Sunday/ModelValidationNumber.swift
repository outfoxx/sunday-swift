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
import PotentJSON

/// Exact numeric input retained for schema validation before storage conversion can round it.
public struct ModelValidationNumber: Swift.Decodable, Swift.Hashable, Swift.Comparable, Swift.Sendable {
  let negative: Bool
  let digits: [Int]
  let exponent: Int

  /// Retains JSON numeric text exactly; other decoders provide their representable numeric precision.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let tree = container as? any TreeValueDecodingContainer,
       let json = tree.decodeTreeValue() as? PotentJSON.JSON {
      guard case .number(let number) = json, let exact = Self(validating: number.value) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a finite number")
      }
      self = exact
    }
    else if let value = try? container.decode(Foundation.Decimal.self), value.isFinite {
      self.init(value.description)
    }
    else {
      let value = try container.decode(Swift.Double.self)
      guard value.isFinite else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a finite number")
      }
      self.init(value.description)
    }
  }

  /// Reads a dynamic numeric value without coercing booleans, strings, or other wire types.
  public init?(value: AnyValue) {
    switch value {
    case .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64,
         .integer, .unsignedInteger, .float16, .float, .double, .decimal:
      self.init(validating: value.description)
    default:
      return nil
    }
  }

  /// Creates an exact decimal value from a finite numeric description or a validated schema literal.
  public init(_ literal: String) {
    guard let value = Self(validating: literal) else {
      preconditionFailure("Expected a finite decimal literal")
    }
    self = value
  }

  /// Parses a finite decimal literal without trapping on malformed input or overflowing its exponent.
  public init?(validating literal: String) {
    let parts = literal.lowercased().split(separator: "e", omittingEmptySubsequences: false)
    guard parts.count <= 2, let mantissa = parts.first, !mantissa.isEmpty else { return nil }
    let negative = mantissa.hasPrefix("-")
    let unsigned = mantissa.hasPrefix("-") || mantissa.hasPrefix("+") ? mantissa.dropFirst() : mantissa[...]
    let fraction = unsigned.split(separator: ".", omittingEmptySubsequences: false)
    guard fraction.count <= 2 else { return nil }
    let rawDigits = fraction.joined().utf8
    guard !rawDigits.isEmpty, rawDigits.allSatisfy({ (48...57).contains($0) }) else { return nil }
    guard let rawExponent = parts.count == 2 ? Int(parts[1]) : 0 else { return nil }
    let adjusted = rawExponent.subtractingReportingOverflow(fraction.count == 2 ? fraction[1].count : 0)
    guard !adjusted.overflow else { return nil }
    var digits = rawDigits.map { Int($0) - 48 }
    var exponent = adjusted.partialValue
    while digits.count > 1 && digits.first == 0 { digits.removeFirst() }
    while digits.count > 1 && digits.last == 0 {
      digits.removeLast()
      let increment = exponent.addingReportingOverflow(1)
      guard !increment.overflow else { return nil }
      exponent = increment.partialValue
    }
    guard !exponent.addingReportingOverflow(digits.count).overflow else { return nil }
    let zero = digits == [0]
    self.negative = negative && !zero
    self.digits = digits
    self.exponent = zero ? 0 : exponent
  }

  /// Whether the exact decimal value has no fractional component.
  public var isInteger: Bool { digits == [0] || exponent >= 0 }

  /// Orders decimal values without conversion to a binary floating-point representation.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.negative != rhs.negative { return lhs.negative }
    if lhs.digits == [0] { return rhs.digits != [0] }
    if rhs.digits == [0] { return false }
    let leftOrder = lhs.digits.count + lhs.exponent
    let rightOrder = rhs.digits.count + rhs.exponent
    if leftOrder != rightOrder {
      return lhs.negative ? leftOrder > rightOrder : leftOrder < rightOrder
    }
    let count = max(lhs.digits.count, rhs.digits.count)
    let left = lhs.digits + Array(repeating: 0, count: count - lhs.digits.count)
    let right = rhs.digits + Array(repeating: 0, count: count - rhs.digits.count)
    return lhs.negative ? right.lexicographicallyPrecedes(left) : left.lexicographicallyPrecedes(right)
  }

  /// Checks exact divisibility by an unsigned decimal significand and base-ten exponent.
  public func isMultipleOf(digits: [Int], exponent: Int) -> Bool {
    guard !digits.isEmpty, digits.allSatisfy({ (0...9).contains($0) }), digits.contains(where: { $0 != 0 }) else {
      return false
    }
    if self.digits == [0] { return true }
    let divisor = Array(digits.drop(while: { $0 == 0 }))
    let difference = self.exponent.subtractingReportingOverflow(exponent)
    guard !difference.overflow, difference.partialValue >= 0 else { return false }
    var scale = difference.partialValue
    var remainder = Self.remainder(self.digits, dividingBy: divisor)
    var power = Self.remainder([1, 0], dividingBy: divisor)
    // Modular exponentiation avoids allocating one digit for every zero in a schema's exponent.
    while scale > 0 && remainder != [0] {
      if scale % 2 == 1 { remainder = Self.remainder(Self.product(remainder, power), dividingBy: divisor) }
      scale /= 2
      if scale > 0 { power = Self.remainder(Self.product(power, power), dividingBy: divisor) }
    }
    return remainder == [0]
  }

  private static func product(_ left: [Int], _ right: [Int]) -> [Int] {
    var result = Array(repeating: 0, count: left.count + right.count)
    for leftIndex in left.indices.reversed() {
      for rightIndex in right.indices.reversed() {
        let index = leftIndex + rightIndex + 1
        let value = result[index] + left[leftIndex] * right[rightIndex]
        result[index] = value % 10
        result[index - 1] += value / 10
      }
    }
    while result.count > 1 && result.first == 0 { result.removeFirst() }
    return result
  }

  private static func remainder(_ dividend: [Int], dividingBy divisor: [Int]) -> [Int] {
    var remainder = [0]
    for digit in dividend {
      remainder.append(digit)
      while remainder.count > 1 && remainder.first == 0 { remainder.removeFirst() }
      while remainder.count > divisor.count ||
        (remainder.count == divisor.count && !remainder.lexicographicallyPrecedes(divisor)) {
        var borrow = 0
        for offset in 0..<remainder.count {
          let index = remainder.count - 1 - offset
          let subtrahend = offset < divisor.count ? divisor[divisor.count - 1 - offset] : 0
          let difference = remainder[index] - subtrahend - borrow
          remainder[index] = (difference + 10) % 10
          borrow = difference < 0 ? 1 : 0
        }
        while remainder.count > 1 && remainder.first == 0 { remainder.removeFirst() }
      }
    }
    return remainder
  }
}
