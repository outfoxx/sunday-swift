//
//  TargetBundle.swift
//  
//
//  Created by Kevin Wooten on 7/5/19.
//

import Foundation


private class Sunday {}

internal extension Bundle {

  static var target: Bundle {
    return Bundle(for: Sunday.self)
  }

}
