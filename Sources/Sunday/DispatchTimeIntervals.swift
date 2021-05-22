//
//  DispatchTimeIntervals.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


extension DispatchTimeInterval {

  var totalMilliseconds: Int {
    switch self {
    case .seconds(let secs): return secs * 1000
    case .milliseconds(let millis): return millis
    case .microseconds(let micros): return micros / 1000
    case .nanoseconds(let nanos): return nanos / 1_000_000
    default: return Int.max
    }
  }

  var totalSeconds: TimeInterval {
    switch self {
    case .seconds(let secs): return Double(secs) * 1000.0
    case .milliseconds(let millis): return Double(millis)
    case .microseconds(let micros): return Double(micros) / 1000.0
    case .nanoseconds(let nanos): return Double(nanos) / 1_000_000.0
    default: return TimeInterval.nan
    }
  }

}
