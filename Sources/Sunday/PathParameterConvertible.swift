//
//  PathParameterConvertible.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/18/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation


protocol CustomPathConvertible {
  var pathDescription: String { get }
}


/**
 * Standard PathParameterConvertible types
 */

extension UUID : CustomPathConvertible {

  var pathDescription: String {
    return uuidString
  }

}
