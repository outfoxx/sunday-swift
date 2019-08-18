//
//  TargetBundle.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


private class SundayServer {}

internal extension Bundle {

  static var target: Bundle {
    return Bundle(for: SundayServer.self)
  }

}
