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


class HeaderParametersTests: XCTestCase {

  func testEncodingArrayValues() throws {

    let values = [MediaType.json, MediaType.cbor]

    let headers = try HeaderParameters.encode(headers: [
      "test": values,
    ])

    XCTAssertEqual(
      headers,
      [
        HTTP.Header(name: "test", value: MediaType.json.value),
        HTTP.Header(name: "test", value: MediaType.cbor.value),
      ]
    )
  }

  func testEncodingStringValues() throws {

    let headers = try HeaderParameters.encode(headers: ["test": ["header"]])

    XCTAssertEqual(headers, [HTTP.Header(name: "test", value: "header")])
  }

  func testEncodingIntegerValues() throws {

    let headers = try HeaderParameters.encode(headers: ["test": 1])

    XCTAssertEqual(headers, [HTTP.Header(name: "test", value: "1")])
  }

  func testEncodingFloatingValues() throws {

    let headers = try HeaderParameters.encode(headers: ["test": 123.456])

    XCTAssertEqual(headers, [HTTP.Header(name: "test", value: "123.456")])
  }

  func testIgnoresNilValues() throws {

    let headers = try HeaderParameters.encode(headers: ["test": nil])

    XCTAssertEqual(headers, [])
  }

  func testCustomHeaderConvertibleValues() throws {

    struct Tester: CustomHeaderConvertible {
      var headerDescription: String { "abcd3f" }
    }

    let headers = try HeaderParameters.encode(headers: ["test": Tester()])

    XCTAssertEqual(headers, [HTTP.Header(name: "test", value: "abcd3f")])
  }

  func testLosslessStringConvertibleValues() throws {

    struct SpecialParam: LosslessStringConvertible {

      let value: String

      init() {
        value = "special-string"
      }

      init?(_ description: String) {
        value = description
      }

      var description: String {
        value
      }

    }

    let headers = try HeaderParameters.encode(headers: ["test": SpecialParam()])

    XCTAssertEqual(headers, [HTTP.Header(name: "test", value: "special-string")])
  }

  func testFailsOnUnknownParameterTypes() throws {

    struct Tester {
      let value = "tester"
    }

    XCTAssertThrowsError(try HeaderParameters.encode(headers: ["test": Tester()])) { error in

      guard case HeaderParameters.Error.unsupportedHeaderParameterValue(let badHeader, let badType) = error else {
        XCTFail("unexpected error")
        return
      }

      XCTAssertEqual(badHeader, "test")
      XCTAssertTrue(badType == Tester.self)
    }
  }

  func testFailsOnInvalidEncodedHeaderValues() throws {

    XCTAssertThrowsError(try HeaderParameters.encode(headers: ["test": "a test\nvalue"])) { error in

      guard case HeaderParameters.Error.invalidEncodedValue(let badHeader, let badValue) = error else {
        XCTFail("unexpected error")
        return
      }

      XCTAssertEqual(badHeader, "test")
      XCTAssertEqual(badValue, "a test\nvalue")
    }
  }

}
