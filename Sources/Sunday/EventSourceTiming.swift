/*
 * Copyright 2026 Outfox, Inc.
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


/// Timing calculations shared by EventSource retry and liveness policies.
enum EventSourceTiming {

  static let retryJitterRange = 0.9 ... 1.0

  private static let retryTimeMaximumMultiplier = 30
  private static let maximumRetryAttempt = Int.bitWidth - 2
  private static let keepaliveTimeoutMultiplier = 3
  private static let keepaliveTimeoutMinimumMilliseconds = 1000

  static func nextRetryAttempt(after retryAttempt: Int) -> Int {
    guard retryAttempt < maximumRetryAttempt else {
      return maximumRetryAttempt
    }
    return max(0, retryAttempt + 1)
  }

  static func retryDelay(
    retryAttempt: Int,
    retryTime: DispatchTimeInterval,
    retryTimeMaximum: DispatchTimeInterval?,
    jitterFactor: Double
  ) -> DispatchTimeInterval {
    let retryTimeMilliseconds = max(0, retryTime.totalMilliseconds)
    let defaultMaximum = multiplyingClamped(
      retryTimeMilliseconds,
      by: retryTimeMaximumMultiplier
    )
    let retryTimeMaximumMilliseconds = max(
      0,
      retryTimeMaximum?.totalMilliseconds ?? defaultMaximum
    )
    let retryMultiplier = 1 << min(max(0, retryAttempt), maximumRetryAttempt)
    let retryDelay = min(
      multiplyingClamped(retryTimeMilliseconds, by: retryMultiplier),
      retryTimeMaximumMilliseconds
    )

    guard retryAttempt > 0, jitterFactor < 1 else {
      return .milliseconds(retryDelay)
    }

    return .milliseconds(Int(Double(retryDelay) * max(0, jitterFactor)))
  }

  static func parseMilliseconds(_ value: String) -> Int? {
    guard !value.isEmpty, value.utf8.allSatisfy({ 48 ... 57 ~= $0 }) else {
      return nil
    }

    return Int(value, radix: 10)
  }

  static func keepaliveTimeout(for keepaliveInterval: Int) -> DispatchTimeInterval {
    let timeout = max(
      keepaliveTimeoutMinimumMilliseconds,
      multiplyingClamped(keepaliveInterval, by: keepaliveTimeoutMultiplier)
    )
    return .milliseconds(timeout)
  }

  static func timeoutCheckInterval(
    configured: DispatchTimeInterval,
    timeout: DispatchTimeInterval
  ) -> DispatchTimeInterval {
    let configuredMilliseconds = max(1, configured.totalMilliseconds)
    let timeoutFractionMilliseconds = max(1, timeout.totalMilliseconds / 3)
    return .milliseconds(min(configuredMilliseconds, timeoutFractionMilliseconds))
  }

  private static func multiplyingClamped(_ value: Int, by multiplier: Int) -> Int {
    let (result, overflow) = value.multipliedReportingOverflow(by: multiplier)
    return overflow ? Int.max : result
  }

}
