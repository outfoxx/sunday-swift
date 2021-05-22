//
//  HeaderParametersTests.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import XCTest
@testable import Sunday


class HeaderParametersTests: XCTestCase {

  func testEncodingArrayValues() throws {

    let values = [MediaType.json, MediaType.cbor]

    let headers = try HeaderParameters.encode(headers: [
      "test": values
    ])

    XCTAssertEqual(headers, [
                    HTTP.Header(name: "test", value: MediaType.json.value),
                    HTTP.Header(name: "test", value: MediaType.cbor.value)]
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

    struct Tester : CustomHeaderConvertible {
      var headerDescription: String { "abcd3f" }
    }

    let headers = try HeaderParameters.encode(headers: ["test": Tester()])

    XCTAssertEqual(headers, [HTTP.Header(name: "test", value: "abcd3f")])
  }

  func testLosslessStringConvertibleValues() throws {

    struct SpecialParam : LosslessStringConvertible {

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
      XCTAssertTrue(error is SundayError)
    }
  }

}
