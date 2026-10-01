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

/// Primitive string representations used by generated Swift storage types.
public enum ModelStringFormat {
  case uuid, url, base64, date, time, dateTime, localDateTime

  /// Checks wire syntax without decoding or constructing an application model.
  public func isValid(_ value: ModelValidationValue, context: inout ModelValidationContext) -> Bool {
    guard let string = value.string else { return context.reject(.invalidValue) }
    let valid: Bool
    switch self {
    case .uuid: valid = UUID(uuidString: string) != nil
    case .url: valid = URL(string: string) != nil
    case .base64: valid = Data(base64Encoded: string) != nil
    case .date, .time, .dateTime, .localDateTime: valid = acceptsDate(string)
    }
    return valid || context.reject(.invalidValue)
  }

  private func acceptsDate(_ value: String) -> Bool {
    let formatter = ISO8601DateFormatter()
    let date = #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#
    let time = #"[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?"#
    let pattern: String
    switch self {
    case .date:
      pattern = date
      formatter.formatOptions = [.withFullDate]
    case .time:
      pattern = time
      formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
    case .localDateTime:
      pattern = date + "[Tt]" + time
      formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
    default:
      pattern = date + "[Tt]" + time + #"(?:[Zz]|[+-][0-9]{2}:[0-9]{2})"#
      formatter.formatOptions = [.withInternetDateTime]
    }
    guard value.range(of: "\\A" + pattern + "\\z", options: .regularExpression) != nil else { return false }
    // Foundation accepts some overflowing calendar dates by carrying into the next month.
    if self != .time && !hasCalendarDate(value) { return false }
    if value.contains(".") { formatter.formatOptions.insert(.withFractionalSeconds) }
    return formatter.date(from: value.uppercased()) != nil
  }

  private func hasCalendarDate(_ value: String) -> Bool {
    let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return false }
    let (year, month, day) = (parts[0], parts[1], parts[2])
    guard (1...12).contains(month) else { return false }
    let leapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    let days = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return (1...days[month - 1]).contains(day)
  }
}
