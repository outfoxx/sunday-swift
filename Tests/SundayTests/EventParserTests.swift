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
@testable import Sunday
import XCTest

class EventParserTests: XCTestCase {

  func testDispatchOfEventsWithLineFeeds() {
    let eventBuffer = "event: hello\nid: 12345\ndata: Hello World!\n\n".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, nil)
    XCTAssertEqual(event.id, "12345")
    XCTAssertEqual(event.event, "hello")
    XCTAssertEqual(event.data, "Hello World!")
  }

  func testDispatchOfEventsWithCarriageReturns() {
    let eventBuffer = "event: hello\rid: 12345\rdata: Hello World!\r\r".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, nil)
    XCTAssertEqual(event.id, "12345")
    XCTAssertEqual(event.event, "hello")
    XCTAssertEqual(event.data, "Hello World!")
  }

  func testDispatchOfEventsWithCarriageReturnLineFeeds() {
    let eventBuffer = "event: hello\r\nid: 12345\r\ndata: Hello World!\r\n\r\n".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, nil)
    XCTAssertEqual(event.id, "12345")
    XCTAssertEqual(event.event, "hello")
    XCTAssertEqual(event.data, "Hello World!")
  }

  func testDispatchOfEventsWithMixedCarriageReturnLineFeeds() {
    let eventBuffer = "event: hello\nid: 12345\rdata: Hello World!\r\n\r\n".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, nil)
    XCTAssertEqual(event.id, "12345")
    XCTAssertEqual(event.event, "hello")
    XCTAssertEqual(event.data, "Hello World!")
  }

  func testDispatchesChunkedEvents() {
    let eventBuffers = [
      "eve".data(using: .utf8)!,
      "nt: hello\nid: 123".data(using: .utf8)!,
      "45\rdata: Hello World!\r".data(using: .utf8)!,
      "\n\r\neve".data(using: .utf8)!,
      "nt: hello\nid: 123".data(using: .utf8)!,
      Data(),
      "45\rdata: Hello World!\r".data(using: .utf8)!,
      "\n\r\n".data(using: .utf8)!,
      "event: hello\nid: 123".data(using: .utf8)!,
      "45\rdata: Hello World!\r\n\r\n".data(using: .utf8)!,
      "45\rdata: Hello World!\r\n\r\n".data(using: .utf8)!,
      "\r\n\r\n\r\n\r\n".data(using: .utf8)!,
    ]

    let parser = EventParser()

    var events: [EventInfo] = []
    eventBuffers.forEach { eventBuffer in
      parser.process(data: eventBuffer) { events.append($0) }
    }

    XCTAssertEqual(events.count, 4)

    let event1 = events.removeFirst()
    XCTAssertEqual(event1.retry, nil)
    XCTAssertEqual(event1.id, "12345")
    XCTAssertEqual(event1.event, "hello")
    XCTAssertEqual(event1.data, "Hello World!")

    let event2 = events.removeFirst()
    XCTAssertEqual(event2.retry, nil)
    XCTAssertEqual(event2.id, "12345")
    XCTAssertEqual(event2.event, "hello")
    XCTAssertEqual(event2.data, "Hello World!")

    let event3 = events.removeFirst()
    XCTAssertEqual(event3.retry, nil)
    XCTAssertEqual(event3.id, "12345")
    XCTAssertEqual(event3.event, "hello")
    XCTAssertEqual(event3.data, "Hello World!")

    let event4 = events.removeFirst()
    XCTAssertEqual(event4.retry, nil)
    XCTAssertEqual(event4.id, nil)
    XCTAssertEqual(event4.event, nil)
    XCTAssertEqual(event4.data, "Hello World!")
  }

  func testConcatenatesDataFields() {
    let eventBuffer = "event: hello\ndata: Hello \ndata: World!\n\n".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, nil)
    XCTAssertEqual(event.id, nil)
    XCTAssertEqual(event.event, "hello")
    XCTAssertEqual(event.data, "Hello \nWorld!")
  }

  func testAllowsEmptyValuesForFields() {
    let eventBuffer = "retry: \nevent: \nid: \ndata: \n\n".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, "")
    XCTAssertEqual(event.id, "")
    XCTAssertEqual(event.event, "")
    XCTAssertEqual(event.data, "")
  }

  func testAllowsEmptyValuesForFieldsWithoutSpaces() {
    let eventBuffer = "retry:\nevent:\nid:\ndata:\n\n".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, "")
    XCTAssertEqual(event.id, "")
    XCTAssertEqual(event.event, "")
    XCTAssertEqual(event.data, "")
  }

  func testAllowsEmptyValuesForFieldsWithoutColons() {
    let eventBuffer = "retry\nevent\nid\ndata\n\n".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, "")
    XCTAssertEqual(event.id, "")
    XCTAssertEqual(event.event, "")
    XCTAssertEqual(event.data, "")
  }

  func testIgnoresCommentLines() {
    let eventBuffer = ": this is a common\nevent\nid\ndata\n\n".data(using: .utf8)!

    let parser = EventParser()

    var events: [EventInfo] = []
    parser.process(data: eventBuffer) { events.append($0) }

    XCTAssertEqual(events.count, 1)
    guard let event = events.first else {
      return
    }

    XCTAssertEqual(event.retry, nil)
    XCTAssertEqual(event.id, "")
    XCTAssertEqual(event.event, "")
    XCTAssertEqual(event.data, "")
  }

}
