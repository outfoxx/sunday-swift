//
//  CustomHeaderConvertible.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


protocol CustomHeaderConvertible {
  var headerDescription: String { get }
}


/**
 * Standard PathParameterConvertible types
 */

extension UUID: CustomHeaderConvertible {
  var headerDescription: String { uuidString }
}
