//
//  AnyTextMediaTypeDecodable.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public struct AnyTextMediaTypeDecodable {
  public let decode: (TextMediaTypeDecoder, String) throws -> Any?

  public static func erase<D: Decodable>(_ type: D.Type = D.self) -> AnyTextMediaTypeDecodable {
    return AnyTextMediaTypeDecodable(decode: { try $0.decode(D.self, from: $1) })
  }

}
