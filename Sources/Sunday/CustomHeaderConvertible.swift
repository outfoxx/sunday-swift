//
//  CustomHeaderConvertible.swift
//  
//
//  Created by Kevin Wooten on 5/21/21.
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
