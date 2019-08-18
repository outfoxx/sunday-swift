//
//  ParameterEncodingEncoder.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Alamofire
import Foundation
import PotentCodables


public struct ParameterEncodingEncoder: MediaTypeEncoder {

  enum Error: Swift.Error {
    case encodedValueNotDictionary
  }

  private static let emptyURL = URL(string: "local://empty")!

  private let encoder: AnyValueEncoder
  private let encoding: ParameterEncoding

  public init(encoder: AnyValueEncoder, encoding: ParameterEncoding) {
    self.encoder = encoder
    self.encoding = encoding
  }

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {

    guard let parameters = try encoder.encodeTree(value).unwrappedValues as? [String: Any] else {
      throw Error.encodedValueNotDictionary
    }

    return try encoding.encode(URLRequest(url: ParameterEncodingEncoder.emptyURL), with: parameters).httpBody ?? Data()
  }

}
