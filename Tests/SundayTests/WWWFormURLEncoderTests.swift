//
//  WWWFormURLEncoderTests.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Sunday
import XCTest

class WWWFormURLEncoderTests: XCTestCase {
  
  func testGenericEncoding() throws {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      try encoder.encode([
        "test/data":  [1, 2, 3],
      ]),
      "test%2Fdata=1&test%2Fdata=2&test%2Fdata=3".data(using: .utf8)
    )
    
  }
  
  func testGenericEncodingFailsWhenNotADictionary() throws {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertThrowsError(try encoder.encode([1, 2, 3]))
  }

  func testKeysArePercentEncoded() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test/data":  [1, 2, 3],
      ]),
      "test%2Fdata=1&test%2Fdata=2&test%2Fdata=3"
    )
  }
  
  func testValuesArePercentEncoded() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  ["1/1", "1/2", "1/3", " !'()~"],
      ]),
      "test=1%2F1&test=1%2F2&test=1%2F3&test=%20!'()~"
    )
  }
  
  func testComplexValuesAreEncoded() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  ["a": 1, "b": 2],
        "c": "3",
      ]),
      "c=3&test%5Ba%5D=1&test%5Bb%5D=2"
    )
  }
  
  func testArraysAreEncodedInBracketedForm() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .bracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  [1, 2, 3]
      ]),
      "test%5B%5D=1&test%5B%5D=2&test%5B%5D=3"
    )
  }
  func testArraysAreEncodedInUnbracketedForm() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  [1, 2, 3]
      ]),
      "test=1&test=2&test=3"
    )
  }

  func testBoolsAreEncodedInNumericForm() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  [true, false]
      ]),
      "test=1&test=0"
    )
  }
  func testBoolsAreEncodedInLiteralForm() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .literal,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  [true, false]
      ]),
      "test=true&test=false"
    )
  }
  
  static let formatter: ISO8601DateFormatter = {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions.insert(.withFractionalSeconds)
    return fmt
  }()
  
  let date1 = formatter.date(from: "2017-05-15T08:30:00.123456789Z")!
  let date2 = formatter.date(from: "2018-06-16T09:40:10.123456789+07:00")!
  
  func testDatesAreEncodedInISOForm() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .numeric,
                                    dateEncoding: .iso8601)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  [date1, date2]
      ]),
      "test=2017-05-15T08%3A30%3A00.123Z&test=2018-06-16T02%3A40%3A10.123Z"
    )
  }
  
  func testDatesAreEncodedInSecondsSinceEpochForm() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .literal,
                                    dateEncoding: .secondsSince1970)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  [date1, date2]
      ]),
      "test=1494837000.123&test=1529116810.123"
    )
  }
  
  func testDatesAreEncodedInMillisecondsSinceEpochForm() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .literal,
                                    dateEncoding: .millisecondsSince1970)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "test":  [date1, date2]
      ]),
      "test=1494837000123&test=1529116810123"
    )
  }
  
  func testNullsAreEncodedAsFlagged() {
    
    let encoder = WWWFormURLEncoder(arrayEncoding: .unbracketed,
                                    boolEncoding: .literal,
                                    dateEncoding: .millisecondsSince1970)
    
    XCTAssertEqual(
      encoder.encodeQueryString(parameters: [
        "flagged":  nil
      ]),
      "flagged"
    )
  }

}
