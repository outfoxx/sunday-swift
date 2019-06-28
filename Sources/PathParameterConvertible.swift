//
//  PathParameterConvertible.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/18/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation


protocol PathParameterConvertible {
  func path() -> String
}


/**
 * Standard PathParameterConvertible types
 */

extension UUID : PathParameterConvertible {

  func path() -> String {
    return uuidString
  }

}
