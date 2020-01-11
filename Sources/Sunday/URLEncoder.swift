//
//  URLEncoder.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCodables


public struct URLEncoder: MediaTypeEncoder {

  public static let `default` = URLEncoder()

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
    /// Encode the `Date` as a UNIX timestamp (floating point seconds since epoch).
    case secondsSince1970

    /// Encode the `Date` as UNIX millisecond timestamp (integer milliseconds since epoch).
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

    private static let iso8601Formatter = ISO8601DateFormatter()
  }

  enum Error: Swift.Error {
    case encodedValueNotDictionary
    case stringEncodingFailed
  }

  private let encoder: AnyValueEncoder
  private let arrayEncoding: ArrayEncoding
  private let boolEncoding: BoolEncoding
  private let dateEncoding: DateEncoding

  public init(arrayEncoding: ArrayEncoding = .bracketed, boolEncoding: BoolEncoding = .numeric,
              dateEncoding: DateEncoding = .iso8601, encoder: AnyValueEncoder = .default) {
    self.encoder = encoder
    self.arrayEncoding = arrayEncoding
    self.boolEncoding = boolEncoding
    self.dateEncoding = dateEncoding
  }

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {

    guard let parameters = try encoder.encodeTree(value).unwrappedValues as? [String: Any] else {
      throw Error.encodedValueNotDictionary
    }

    guard let data = encodeQueryString(parameters: parameters).data(using: .ascii) else {
      throw Error.stringEncodingFailed
    }

    return data
  }

  public func encodeQueryString(parameters: Parameters) -> String {
    var components: [(String, String)] = []

    for key in parameters.keys.sorted(by: <) {
        let value = parameters[key]!
        components += encodeQueryComponent(fromKey: key, value: value)
    }
    return components.map { "\($0)=\($1)" }.joined(separator: "&")
  }

  public func encodeQueryComponent(fromKey key: String, value: Any) -> [(String, String)] {
    var components: [(String, String)] = []

    if let dictionary = value as? [String: Any] {
      for (nestedKey, value) in dictionary {
        components += encodeQueryComponent(fromKey: "\(key)[\(nestedKey)]", value: value)
      }
    }
    else if let array = value as? [Any] {
      for value in array {
        components += encodeQueryComponent(fromKey: arrayEncoding.encode(key: key), value: value)
      }
    }
    else if let date = value as? Date {
      components.append((escape(key), escape(dateEncoding.encode(value: date))))
    }
    else if let value = value as? NSNumber {
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        components.append((escape(key), escape(boolEncoding.encode(value: value.boolValue))))
      }
      else {
        components.append((escape(key), escape("\(value)")))
      }
    }
    else if let bool = value as? Bool {
      components.append((escape(key), escape(boolEncoding.encode(value: bool))))
    }
    else {
      components.append((escape(key), escape("\(value)")))
    }

    return components
  }

  public func escape(_ string: String) -> String {
      let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
      let subDelimitersToEncode = "!$&'()*+,;="

      var allowedCharacterSet = CharacterSet.urlQueryAllowed
      allowedCharacterSet.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

      return string.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? string
  }

}
