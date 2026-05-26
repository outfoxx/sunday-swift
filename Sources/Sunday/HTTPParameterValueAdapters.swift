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


/// Utilities for adapting arbitrary API parameter values to Sunday request parameter bags.
public enum ParameterValues {

  /// Encodes an encodable value into a Sendable parameter value.
  public static func encode<T: Encodable>(_ value: T) throws -> (any Sendable)? {
    try encode(AnyValueEncoder.default.encodeTree(value).unwrapped)
  }

  /// Converts a raw value into a Sendable parameter value.
  public static func encode(_ value: Any?) throws -> (any Sendable)? {
    try httpParameterValue(value)
  }

}

protocol HTTPParameterValue: Sendable {}

protocol HTTPParameterArrayAdapter {
  var httpParameterValues: [any Sendable] { get }
}

protocol HTTPParameterDictionaryAdapter {
  var httpParameterValues: [String: (any Sendable)?] { get }
}

protocol HTTPParameterOptionalAdapter {
  var httpParameterValue: (any Sendable)? { get }
}

struct HTTPParameterArray: WWWFormURLEncoder.ParameterValue,
  URI.Template.ParameterValue,
  HTTPParameterArrayAdapter {

  let httpParameterValues: [any Sendable]
}

struct HTTPParameterDictionary: WWWFormURLEncoder.ParameterValue,
  URI.Template.ParameterValue,
  HTTPParameterDictionaryAdapter {

  let httpParameterValues: [String: (any Sendable)?]
}

extension Array: WWWFormURLEncoder.ParameterValue where Element: WWWFormURLEncoder.ParameterValue {}
extension Array: URI.Template.ParameterValue where Element: URI.Template.ParameterValue {}

extension Array: HTTPParameterArrayAdapter where Element: HTTPParameterValue {
  var httpParameterValues: [any Sendable] {
    compactMap { element in
      if let optionalElement = element as? HTTPParameterOptionalAdapter {
        return optionalElement.httpParameterValue
      }
      return element
    }
  }
}

extension Dictionary: WWWFormURLEncoder.ParameterValue where Key == String, Value: WWWFormURLEncoder.ParameterValue {}
extension Dictionary: URI.Template.ParameterValue where Key == String, Value: URI.Template.ParameterValue {}

extension Dictionary: HTTPParameterDictionaryAdapter where Key == String, Value: HTTPParameterValue {
  var httpParameterValues: [String: (any Sendable)?] {
    [String: (any Sendable)?](uniqueKeysWithValues: map { key, value in
      if let optionalValue = value as? HTTPParameterOptionalAdapter {
        return (key, optionalValue.httpParameterValue)
      }
      return (key, value)
    })
  }
}

extension Optional: WWWFormURLEncoder.ParameterValue where Wrapped: WWWFormURLEncoder.ParameterValue {}
extension Optional: URI.Template.ParameterValue where Wrapped: URI.Template.ParameterValue {}

extension Optional: HTTPParameterOptionalAdapter where Wrapped: HTTPParameterValue {
  var httpParameterValue: (any Sendable)? {
    switch self {
    case .some(let value):
      return value
    case .none:
      return nil
    }
  }
}

private func httpParameterValue(_ value: Any?) throws -> (any Sendable)? {
  switch value {
  case nil, is NSNull:
    return nil
  case let value as [String: Any?]:
    return HTTPParameterDictionary(
      httpParameterValues: try Dictionary(uniqueKeysWithValues: value.map { key, value in
        (key, try httpParameterValue(value))
      })
    )
  case let value as [String: Any]:
    return HTTPParameterDictionary(
      httpParameterValues: try Dictionary(uniqueKeysWithValues: value.map { key, value in
        (key, try httpParameterValue(value))
      })
    )
  case let value as [Any?]:
    return HTTPParameterArray(httpParameterValues: try value.compactMap { try httpParameterValue($0) })
  case let value as [Any]:
    return HTTPParameterArray(httpParameterValues: try value.compactMap { try httpParameterValue($0) })
  case let value as any HTTPParameterOptionalAdapter:
    return value.httpParameterValue
  case let value as any HTTPParameterDictionaryAdapter:
    let parameterValues = try value.httpParameterValues.map { key, value in
      (key, try httpParameterValue(value))
    }
    return HTTPParameterDictionary(
      httpParameterValues: [String: (any Sendable)?](uniqueKeysWithValues: parameterValues)
    )
  case let value as any HTTPParameterArrayAdapter:
    return HTTPParameterArray(
      httpParameterValues: try value.httpParameterValues.compactMap { try httpParameterValue($0) }
    )
  case let value as any HTTPParameterValue:
    return value
  case let value as any WWWFormURLEncoder.ParameterValue:
    return value
  case let value as any URI.Template.ParameterValue:
    return value
  default:
    throw ParameterValueError.unsupportedParameterType(
      typeName: value.map { String(reflecting: Swift.type(of: $0)) } ?? "nil"
    )
  }
}

/// Errors thrown while adapting API parameter values.
public enum ParameterValueError: Error, Sendable {

  /// The value cannot be represented as a Sunday request parameter.
  case unsupportedParameterType(typeName: String)

}
