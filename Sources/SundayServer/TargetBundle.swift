//
//  TargetBundle.swift
//
//
//  Created by Kevin Wooten on 7/5/19.
//

import Foundation


private class SundayServer {}

internal extension Bundle {

  static var target: Bundle {
    return Bundle(for: SundayServer.self)
  }

}
