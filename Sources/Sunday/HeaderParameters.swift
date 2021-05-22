//
//  HeaderParameters.swift
//  
//
//  Created by Kevin Wooten on 5/21/21.
//

import Foundation


enum HeaderParameters {

  static func encode(headers: [String: Any?]) throws -> HTTP.HeaderList{

    let headersMultiMap =
      try headers.compactMapValues { headerValue in
        try headerValue.map { try encode(parameter: $0) }
      }

    return headersMultiMap.flatMap { name, values in
      values.map { HTTP.Header(name: name, value: $0) }
    }
  }

  private static func encode(parameter: Any) throws -> [String] {

    if let array = parameter as? Array<Any> {
      return try array.map { try encode(value: $0) }
    }

    return [try encode(value: parameter)]
  }

  private static func encode(value: Any) throws -> String {
    switch value {

    case let header as CustomHeaderConvertible:
      return header.headerDescription

    case let string as LosslessStringConvertible:
      return string.description

    default:
      throw SundayError.requestEncodingFailed(reason: .unsupportedHeaderParameterValue(value))
    }
  }

}
