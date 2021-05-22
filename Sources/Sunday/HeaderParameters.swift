//
//  HeaderParameters.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


enum HeaderParameters {

  enum Error : Swift.Error {
    case unsupportedHeaderParameterValue(header: String, type: Any.Type)
    case invalidEncodedValue(header: String, invalidValue: String)
  }

  static func encode(headers: [String: Any?]) throws -> HTTP.HeaderList {

    let groupedList: [(String, [String])] =
      try headers.compactMap { headerName, headerParameter in

        guard let headerParameter = headerParameter else {
          return nil
        }

        let headerValues = try encode(header: headerName, parameter: headerParameter)

        return (headerName, headerValues)
      }

    return groupedList.flatMap { name, values in
      values.map { HTTP.Header(name: name, value: $0) }
    }
  }

  private static let disallowedCharacters = CharacterSet(charactersIn: "\0\r\n")

  private static func encode(header: String, parameter: Any) throws -> [String] {

    if let array = parameter as? Array<Any> {
      return try array.map { try encode(header: header, value: $0) }
    }

    return [try encode(header: header, value: parameter)]
  }

  private static func encode(header: String, value: Any) throws -> String {

    let encoded: String

    switch value {

    case let header as CustomHeaderConvertible:
      encoded = header.headerDescription

    case let string as LosslessStringConvertible:
      encoded = string.description

    default:
      throw Error.unsupportedHeaderParameterValue(header: header, type: type(of: value))
    }

    try validate(header: header, encoded: encoded)

    return encoded
  }

  private static func validate(header: String, encoded: String) throws {

    guard
      encoded.canBeConverted(to: .nonLossyASCII),
      encoded.rangeOfCharacter(from: disallowedCharacters) == nil
    else {
      throw Error.invalidEncodedValue(header: header, invalidValue: encoded)
    }

  }

}
