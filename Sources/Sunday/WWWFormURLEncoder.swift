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
import Synchronization


public struct WWWFormURLEncoder: MediaTypeEncoder {

  /// Marker protocol for values supported by form and query parameter encoding.
  public protocol ParameterValue: Sendable {}

  public static let `default` = WWWFormURLEncoder()

  /// Configures how `Array` parameters are encoded.
  ///
  /// - bracketed: An empty set of square brackets is appended to the key for every value. This is the default behavior.
  /// - unbracketed: No brackets are appended. The key is encoded as is.
  public enum ArrayEncoding: Sendable {
    case bracketed, unbracketed

    func encode(key: String) -> String {
      switch self {
      case .bracketed:
        return "\(key)[]"
      case .unbracketed:
        return key
      }
    }
  }

  /// Configures how `Bool` parameters are encoded.
  ///
  /// - numeric: Encode `true` as `1` and `false` as `0`. This is the default behavior.
  /// - literal: Encode `true` and `false` as string literals.
  public enum BoolEncoding: Sendable {
    case numeric, literal

    func encode(value: Bool) -> String {
      switch self {
      case .numeric:
        return value ? "1" : "0"
      case .literal:
        return value ? "true" : "false"
      }
    }
  }

  /// Configures how `Date` parameters are encoded.
  ///
  public enum DateEncoding: Sendable {
    private static let iso8601Formatter = Mutex(Self.makeISO8601Formatter())

    /// Encode the `Date` as a UNIX timestamp (decimal seconds since epoch).
    case secondsSince1970

    /// Encode the `Date` as UNIX millisecond timestamp (milliseconds since epoch).
    case millisecondsSince1970

    /// Encode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
    case iso8601

    func encode(value: Date) -> String {
      switch self {
      case .secondsSince1970:
        return "\(value.timeIntervalSince1970)"
      case .millisecondsSince1970:
        return String(format: "%.0f", value.timeIntervalSince1970 * 1000)
      case .iso8601:
        return Self.iso8601Formatter.withLock { $0.string(from: value) }
      }
    }

    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions.insert(.withFractionalSeconds)
      return formatter
    }
  }

  /// Errors thrown by the form URL encoder.
  public enum Error: Swift.Error {
    /// The encoded value was not a dictionary of form parameters.
    case encodedValueNotDictionary

    /// The encoded string could not be converted to UTF-8 data.
    case stringEncodingFailed

    /// A parameter value cannot be encoded by the form encoder.
    case unsupportedParameterType(name: String, type: Any.Type)
  }

  // Safe because Sunday stores the configured encoder privately and never mutates
  // its configuration after initialization; encoding itself is synchronous.
  nonisolated(unsafe) private let encoder: AnyValueEncoder
  private let arrayEncoding: ArrayEncoding
  private let boolEncoding: BoolEncoding
  private let dateEncoding: DateEncoding

  /**
   * Creates a form URL encoder.
   *
   * Configure a custom `AnyValueEncoder` before passing it here and do not
   * mutate it afterward. Sunday retains and uses it directly during
   * synchronous encoding.
   */
  public init(
    arrayEncoding: ArrayEncoding = .bracketed,
    boolEncoding: BoolEncoding = .numeric,
    dateEncoding: DateEncoding = .iso8601,
    encoder: AnyValueEncoder = .default
  ) {
    self.encoder = encoder
    self.arrayEncoding = arrayEncoding
    self.boolEncoding = boolEncoding
    self.dateEncoding = dateEncoding
  }

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {

    guard let allParameters = try encoder.encodeTree(value).unwrapped as? [String: Any] else {
      throw Error.encodedValueNotDictionary
    }

    let parameters = Dictionary(uniqueKeysWithValues: allParameters.map { key, value in
      (key, Self.parameterValue(value))
    })

    guard let data = try encodeQueryString(parameters: parameters).data(using: .utf8) else {
      throw Error.stringEncodingFailed
    }

    return data
  }

  public func encodeQueryString(parameters: Parameters) throws -> String {
    var components: [String] = []

    for (key, value) in parameters.sorted(by: { left, right in left.key < right.key }) {
      components += try encodeQueryComponent(fromKey: key, value: Self.formParameterValue(name: key, value))
    }
    return components.joined(separator: "&")
  }

  public func encodeQueryComponent(fromKey key: String, value: (any ParameterValue)?) throws -> [String] {
    var components: [String] = []

    if let dictionary = value as? HTTPParameterDictionaryAdapter {
      for nestedKey in dictionary.httpParameterValues.keys.sorted(by: <) {
        let nestedValue = dictionary.httpParameterValues[nestedKey] ?? nil
        components += try encodeQueryComponent(
          fromKey: "\(key)[\(nestedKey)]",
          value: Self.formParameterValue(name: key, nestedValue)
        )
      }
    }
    else if let array = value as? HTTPParameterArrayAdapter {
      for value in array.httpParameterValues {
        components += try encodeQueryComponent(
          fromKey: arrayEncoding.encode(key: key),
          value: Self.formParameterValue(name: key, value)
        )
      }
    }
    else if let date = value as? Date {
      components.append(Self.encodeURIComponent(key) + "=" + Self.encodeURIComponent(dateEncoding.encode(value: date)))
    }
    else if let value = value as? NSNumber {
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        components
          .append(
            Self.encodeURIComponent(key) + "=" + Self
              .encodeURIComponent(boolEncoding.encode(value: value.boolValue))
          )
      }
      else {
        components.append(Self.encodeURIComponent(key) + "=" + Self.encodeURIComponent("\(value)"))
      }
    }
    else if let bool = value as? Bool {
      components.append(Self.encodeURIComponent(key) + "=" + Self.encodeURIComponent(boolEncoding.encode(value: bool)))
    }
    else if let value = value as? AnyFormParameterValue {
      components.append(Self.encodeURIComponent(key) + "=" + Self.encodeURIComponent(try Self.scalarString(value)))
    }
    else if let value = value {
      components.append(Self.encodeURIComponent(key) + "=" + Self.encodeURIComponent("\(value)"))
    }
    else {
      components.append(Self.encodeURIComponent(key))
    }

    return components
  }

  private static func scalarString(_ value: AnyFormParameterValue) throws -> String {
    if let stringValue = value.value as? LosslessStringConvertible {
      return stringValue.description
    }
    if let rawValue = value.value as? any RawRepresentable {
      return String(describing: rawValue.rawValue)
    }
    throw Error.unsupportedParameterType(name: value.name, type: type(of: value.value))
  }

  private static let escapeCharacters = CharacterSet(charactersIn: " *;:@&=+$,/?%#[]").inverted

  public static func encodeURIComponent(_ string: String) -> String {
    return string.addingPercentEncoding(withAllowedCharacters: escapeCharacters) ?? string
  }

  private static func formParameterValue(
    name: String,
    _ value: (any Sendable)?
  ) throws -> (any ParameterValue)? {
    guard let value else {
      return nil
    }
    if let dictionary = value as? HTTPParameterDictionaryAdapter {
      return HTTPParameterDictionary(
        httpParameterValues: try Dictionary(uniqueKeysWithValues: dictionary.httpParameterValues.map { key, value in
          (key, try formParameterValue(name: name, value))
        })
      )
    }
    if let array = value as? HTTPParameterArrayAdapter {
      return HTTPParameterArray(httpParameterValues: try array.httpParameterValues.compactMap { value in
        try formParameterValue(name: name, value)
      })
    }
    if let value = value as? any ParameterValue {
      return value
    }
    if value is LosslessStringConvertible || value is any RawRepresentable {
      return AnyFormParameterValue(name: name, value: value)
    }
    throw Error.unsupportedParameterType(name: name, type: type(of: value))
  }

  private static func parameterValue(_ value: Any?) -> (any ParameterValue)? {
    switch value {
    case nil:
      return nil
    case let value as [String: Any]:
      return HTTPParameterDictionary(
        httpParameterValues: Dictionary(uniqueKeysWithValues: value.map { key, value in (key, parameterValue(value)) })
      )
    case let value as [Any]:
      return HTTPParameterArray(httpParameterValues: value.compactMap { parameterValue($0) })
    case let value as any ParameterValue:
      return value
    case let value?:
      return String(describing: value)
    }
  }

}

private struct AnyFormParameterValue: WWWFormURLEncoder.ParameterValue {
  let name: String
  let value: any Sendable
}

extension Bool: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension String: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Int: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Int8: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Int16: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Int32: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Int64: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension UInt: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension UInt8: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension UInt16: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension UInt32: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension UInt64: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Float: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Double: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Decimal: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension NSNumber: HTTPParameterValue, WWWFormURLEncoder.ParameterValue {}
extension Date: HTTPParameterValue, WWWFormURLEncoder.ParameterValue {}
extension URL: HTTPParameterValue, WWWFormURLEncoder.ParameterValue {}
extension UUID: HTTPParameterValue, WWWFormURLEncoder.ParameterValue, URI.Template.ParameterValue {}
extension Data: HTTPParameterValue, WWWFormURLEncoder.ParameterValue {}
extension MediaType: HTTPParameterValue, WWWFormURLEncoder.ParameterValue {}
