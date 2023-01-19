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


public struct WWWFormURLEncoder: MediaTypeEncoder {

  public static let `default` = WWWFormURLEncoder()

  /// Configures how `Array` parameters are encoded.
  ///
  /// - bracketed: An empty set of square brackets is appended to the key for every value. This is the default behavior.
  /// - unbracketed: No brackets are appended. The key is encoded as is.
  public enum ArrayEncoding {
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
  public enum BoolEncoding {
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
  public enum DateEncoding {
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
        return Self.iso8601Formatter.string(from: value)
      }
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
      let fmt = ISO8601DateFormatter()
      fmt.formatOptions.insert(.withFractionalSeconds)
      return fmt
    }()
  }

  enum Error: Swift.Error {
    case encodedValueNotDictionary
    case stringEncodingFailed
  }

  private let encoder: AnyValueEncoder
  private let arrayEncoding: ArrayEncoding
  private let boolEncoding: BoolEncoding
  private let dateEncoding: DateEncoding

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

    guard let parameters = try encoder.encodeTree(value).compactUnwrapped as? [String: Any] else {
      throw Error.encodedValueNotDictionary
    }

    guard let data = encodeQueryString(parameters: parameters).data(using: .utf8) else {
      throw Error.stringEncodingFailed
    }

    return data
  }

  public func encodeQueryString(parameters: Parameters) -> String {
    var components: [String] = []

    for (key, value) in parameters.sorted(by: { left, right in left.key < right.key }) {
      components += encodeQueryComponent(fromKey: key, value: value)
    }
    return components.joined(separator: "&")
  }

  public func encodeQueryComponent(fromKey key: String, value: Any?) -> [String] {
    var components: [String] = []

    if let dictionary = value as? [String: Any] {
      for nestedKey in dictionary.keys.sorted(by: <) {
        let nestedValue = dictionary[nestedKey]!
        components += encodeQueryComponent(fromKey: "\(key)[\(nestedKey)]", value: nestedValue)
      }
    }
    else if let array = value as? [Any] {
      for value in array {
        components += encodeQueryComponent(fromKey: arrayEncoding.encode(key: key), value: value)
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
    else if let value = value {
      components.append(Self.encodeURIComponent(key) + "=" + Self.encodeURIComponent("\(value)"))
    }
    else {
      components.append(Self.encodeURIComponent(key))
    }

    return components
  }

  private static let escapeCharacters = CharacterSet(charactersIn: " *;:@&=+$,/?%#[]").inverted

  public static func encodeURIComponent(_ string: String) -> String {
    return string.addingPercentEncoding(withAllowedCharacters: escapeCharacters) ?? string
  }

}
