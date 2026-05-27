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
import Sunday
import XCTest


struct UnsupportedParameterValue {}

private func requireSendable<T: Sendable>(_: T.Type) {}


class WWWFormURLEncoderTests: XCTestCase {

  func testGenericEncoding() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encode([
        "test/data": [1, 2, 3],
      ]),
      Data("test%2Fdata=1&test%2Fdata=2&test%2Fdata=3".utf8)
    )

  }

  func testGenericEncodingFailsWhenNotADictionary() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertThrowsError(try encoder.encode([1, 2, 3]))
  }

  func testKeysArePercentEncoded() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test/data": [1, 2, 3],
      ]),
      "test%2Fdata=1&test%2Fdata=2&test%2Fdata=3"
    )
  }

  func testValuesArePercentEncoded() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": ["1/1", "1/2", "1/3", " !'()~"],
      ]),
      "test=1%2F1&test=1%2F2&test=1%2F3&test=%20!'()~"
    )
  }

  func testComplexValuesAreEncoded() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": ["a": 1, "b": 2],
        "c": "3",
      ]),
      "c=3&test%5Ba%5D=1&test%5Bb%5D=2"
    )
  }

  func testEncodableParameterValuesAreEncoded() throws {

    final class QueryObject: Encodable {
      var first: Int = 1
      var second: String = "2"

      enum CodingKeys: String, CodingKey {
        case first = "a"
        case second = "b"
      }
    }

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": try ParameterValues.encode(QueryObject()),
        "c": try ParameterValues.encode("3"),
      ]),
      "c=3&test%5Ba%5D=1&test%5Bb%5D=2"
    )
  }

  func testUnsupportedParameterValueFails() {

    requireSendable(ParameterValueError.self)

    XCTAssertThrowsError(try ParameterValues.encode(UnsupportedParameterValue())) { error in
      guard case let ParameterValueError.unsupportedParameterType(typeName) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }

      XCTAssertEqual(typeName, "SundayTests.UnsupportedParameterValue")
    }
  }

  func testArraysAreEncodedInBracketedForm() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .bracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": [1, 2, 3],
      ]),
      "test%5B%5D=1&test%5B%5D=2&test%5B%5D=3"
    )
  }

  func testArraysAreEncodedInUnbracketedForm() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": [1, 2, 3],
      ]),
      "test=1&test=2&test=3"
    )
  }

  func testBoolsAreEncodedInNumericForm() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": [true, false],
      ]),
      "test=1&test=0"
    )
  }

  func testBoolsAreEncodedInLiteralForm() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .literal,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": [true, false],
      ]),
      "test=true&test=false"
    )
  }

  static func date(from value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: value)!
  }

  let date1 = date(from: "2017-05-15T08:30:00.123456789Z")
  let date2 = date(from: "2018-06-16T09:40:10.123456789+07:00")

  func testDatesAreEncodedInISOForm() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .numeric,
      dateEncoding: .iso8601
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": [date1, date2],
      ]),
      "test=2017-05-15T08%3A30%3A00.123Z&test=2018-06-16T02%3A40%3A10.123Z"
    )
  }

  func testDatesAreEncodedInSecondsSinceEpochForm() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .literal,
      dateEncoding: .secondsSince1970
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": [date1, date2],
      ]),
      "test=1494837000.123&test=1529116810.123"
    )
  }

  func testDatesAreEncodedInMillisecondsSinceEpochForm() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .literal,
      dateEncoding: .millisecondsSince1970
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "test": [date1, date2],
      ]),
      "test=1494837000123&test=1529116810123"
    )
  }

  func testNullsAreEncodedAsFlagged() throws {

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .literal,
      dateEncoding: .millisecondsSince1970
    )

    XCTAssertEqual(
      try encoder.encodeQueryString(parameters: [
        "flagged": nil,
      ]),
      "flagged"
    )
  }

  func testFailsWithUnsupportedHTTPParameterValue() throws {

    struct SpecialType: Sendable {}

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .literal,
      dateEncoding: .millisecondsSince1970
    )

    XCTAssertThrowsError(try encoder.encodeQueryString(parameters: ["id": SpecialType()])) { error in

      guard case let WWWFormURLEncoder.Error.unsupportedParameterType(name: paramName, type: paramType) = error else {
        return XCTFail("unexpected error")
      }

      XCTAssertEqual(paramName, "id")
      XCTAssertTrue(paramType == SpecialType.self)
    }
  }

  func testFailsWithUnsupportedNestedHTTPParameterValue() throws {

    struct SpecialType: Sendable {}

    let encoder = WWWFormURLEncoder(
      arrayEncoding: .unbracketed,
      boolEncoding: .literal,
      dateEncoding: .millisecondsSince1970
    )

    XCTAssertThrowsError(try encoder.encodeQueryString(parameters: ["id": ["value": SpecialType()]])) { error in

      guard case let WWWFormURLEncoder.Error.unsupportedParameterType(name: paramName, type: paramType) = error else {
        return XCTFail("unexpected error")
      }

      XCTAssertEqual(paramName, "id")
      XCTAssertTrue(paramType == [String: SpecialType].self)
    }
  }

}
