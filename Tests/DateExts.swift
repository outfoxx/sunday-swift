//
//  DateExts.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/15/19.
//  Copyright © 2019 Outfox, Inc. All rights reserved.
//

import Foundation


extension Date {

  static func millisecondDate() -> Date {
    let seconds = Date().timeIntervalSince1970
    return Date(timeIntervalSince1970: (seconds * 1000.0).rounded() / 1000.0)
  }

  init(millisecondsSince1970: Int64) {
    self.init(timeIntervalSince1970: Double(millisecondsSince1970) / 1000.0)
  }

  var millisecondsSince1970: Int64 {
    return Int64(timeIntervalSince1970 * 1000.0)
  }

}
