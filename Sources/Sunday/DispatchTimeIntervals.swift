/*
 * Copyright 2021 Outfox, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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
