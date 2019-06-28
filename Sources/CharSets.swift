//
//  CharSets.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/28/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation


public struct CharSets {

  public enum Error : Swift.Error {
    case invalidCharSetName
  }

  public static func determineEncoding(of mediaType: MediaType, default: String.Encoding = .utf8) throws -> String.Encoding {
    guard let charset = mediaType.parameter(.charSet) else { return `default` }

    let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)

    guard encoding != kCFStringEncodingInvalidId else {
      throw Error.invalidCharSetName
    }

    return String.Encoding(rawValue: UInt(encoding))
  }

}
