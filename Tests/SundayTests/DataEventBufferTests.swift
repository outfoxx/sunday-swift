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


class DataEventBufferTests: XCTestCase {

  func testEventStreamFlushesCRLFPairBoundary() throws {

    let response =
      try XCTUnwrap(HTTPURLResponse(
        url: URL(string: "http://example.com/events")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: [
          HTTP.StdHeaders.contentType: MediaType.eventStream.value,
        ]
      ))

    var buffer = DataEventBuffer(response: response)

    let event = "data: hello\r\n\r\n"
    var chunks: [Data] = []
    for byte in event.utf8 {
      if let chunk = buffer.append(byte) {
        chunks.append(chunk)
      }
    }

    XCTAssertEqual(chunks.count, 1)
    XCTAssertEqual(String(data: try XCTUnwrap(chunks.first), encoding: .utf8), event)
  }

  func testEventStreamFlushResetsBoundaryState() throws {

    let response =
      try XCTUnwrap(HTTPURLResponse(
        url: URL(string: "http://example.com/events")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: [
          HTTP.StdHeaders.contentType: MediaType.eventStream.value,
        ]
      ))

    var buffer = DataEventBuffer(response: response)

    for byte in "data: hello\n\n".utf8 {
      _ = buffer.append(byte)
    }

    XCTAssertNil(buffer.append(0x0A))
  }

  func testEventStreamDetectsBoundaryAcrossCapacityFlush() throws {

    let response =
      try XCTUnwrap(HTTPURLResponse(
        url: URL(string: "http://example.com/events")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: [
          HTTP.StdHeaders.contentType: MediaType.eventStream.value,
        ]
      ))

    var buffer = DataEventBuffer(response: response)

    let prefix = "data: "
    let event = prefix + String(repeating: "a", count: 4096 - prefix.utf8.count - 1) + "\n\n"
    var chunks: [Data] = []
    for byte in event.utf8 {
      if let chunk = buffer.append(byte) {
        chunks.append(chunk)
      }
    }

    XCTAssertEqual(chunks.count, 2)
    XCTAssertEqual(chunks[0].count, 4096)
    XCTAssertEqual(String(data: chunks[1], encoding: .utf8), "\n")
  }
}
