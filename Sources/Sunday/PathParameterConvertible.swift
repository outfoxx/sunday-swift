//
//  PathParameterConvertible.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


protocol CustomPathConvertible {
  var pathDescription: String { get }
}


/**
 * Standard PathParameterConvertible types
 */

extension UUID: CustomPathConvertible {

  var pathDescription: String {
    return uuidString
  }

}
