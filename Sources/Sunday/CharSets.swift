//
//  CharSets.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public enum CharSets {

  public enum Error: Swift.Error {
    case invalidCharSetName
  }

  public static func determineEncoding(
    of mediaType: MediaType,
    default: String.Encoding = .utf8
  ) throws -> String.Encoding {

    guard let charset = mediaType.parameter(.charSet) else { return `default` }

    let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)

    guard encoding != kCFStringEncodingInvalidId else {
      throw Error.invalidCharSetName
    }

    return String.Encoding(rawValue: UInt(encoding))
  }

}
