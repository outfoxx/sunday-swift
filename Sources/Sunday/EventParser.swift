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


struct EventInfo {
  var retry: String?
  var event: String?
  var id: String?
  var data: String?
}

class EventParser {

  static let stringEncoding: String.Encoding = .utf8

  private var unprocessedData: Data?

  func process(data: Data, dispatcher: (EventInfo) throws -> Void) rethrows {

    let eventStrings: [String]

    if var availableData = unprocessedData {
      unprocessedData = nil

      availableData.append(data)

      eventStrings = extractEventStrings(data: availableData)
    }
    else {

      eventStrings = extractEventStrings(data: data)
    }

    if eventStrings.isEmpty {
      return
    }

    try Self.parseAndDispatchEvents(eventStrings: eventStrings, dispatcher: dispatcher)
  }

  private func extractEventStrings(data: Data) -> [String] {
    var data = data

    var eventStrings: [String] = []

    while !data.isEmpty {

      // Find event separator or save data and exit
      guard let eventSeparatorRange = Self.findEventSeparator(in: data) else {
        unprocessedData = data
        break
      }

      // Split into event data and rest
      let eventData = data.subdata(in: 0 ..< eventSeparatorRange.startIndex)
      data = data.subdata(in: eventSeparatorRange.endIndex ..< data.count)

      // Conver to string and save
      guard let eventString = String(data: eventData, encoding: Self.stringEncoding) else {
        // ignore invalid messages
        continue
      }
      eventStrings.append(eventString)
    }

    return eventStrings
  }

  private static func findEventSeparator(in data: Data) -> Range<Int>? {

    for idx in 0 ..< data.count {
      let byte = data[idx]

      switch byte {

      // line-feed
      case 0xA:
        // if next char is same,
        // we found a separator
        if data.count > idx + 1, data[idx + 1] == 0xA {
          return idx ..< idx + 2
        }

      // carriage-return
      case 0xD:
        // if next char is same,
        // we found a separator
        if data.count > idx + 1, data[idx + 1] == 0xD {
          return idx ..< idx + 2
        }

        // if next is line-feed, and pattern
        // repeats, we found a separator.
        if
          data.count > idx + 3,
          data[idx + 1] == 0xA,
          data[idx + 2] == 0xD,
          data[idx + 3] == 0xA
        {
          return idx ..< idx + 4
        }

      default:
        continue
      }

    }

    return nil
  }

  private static func parseAndDispatchEvents(
    eventStrings: [String],
    dispatcher: (EventInfo) throws -> Void
  ) rethrows {

    for eventString in eventStrings where !eventString.isEmpty {

      let event = parseEvent(string: eventString)

      try dispatcher(event)
    }
  }

  private static let lineSeparators = CharacterSet(charactersIn: "\r\n")

  private static func parseEvent(string: String) -> EventInfo {

    var info = EventInfo()

    for line in string.components(separatedBy: Self.lineSeparators) {
      if line.isEmpty {
        // lines should not be empty but for streams that use
        // cr-lf pairs, the splitting will cause empty lines
        continue
      }

      let key: Substring
      let value: Substring

      if let keyValueSeparatorIdx = line.firstIndex(of: ":") {
        key = line[line.startIndex ..< keyValueSeparatorIdx]
        value = line[line.index(after: keyValueSeparatorIdx)...]
      }
      else {
        key = line[line.startIndex...]
        value = ""
      }

      switch key {

      case "retry":
        info.retry = trimEventField(string: value)

      case "event":
        info.event = trimEventField(string: value)

      case "id":
        info.id = trimEventField(string: value)

      case "data":
        if let currentData = info.data {
          info.data = currentData + trimEventField(string: value) + "\n"
        }
        else {
          info.data = trimEventField(string: value) + "\n"
        }

      case "":
        // comment do nothing
        break

      default:
        continue
      }

    }

    if let data = info.data, data.last == "\n" {
      info.data = String(data[data.startIndex ..< data.index(before: data.endIndex)])
    }

    return info
  }

  private static func trimEventField(string: Substring) -> String {
    if string.first == " " {
      return String(string.dropFirst())
    }
    return String(string)
  }

}
