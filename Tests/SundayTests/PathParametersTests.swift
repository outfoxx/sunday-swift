//
//  PathParametersTests.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

@testable import Sunday
import XCTest


class PathParametersTest: XCTestCase {

  func testMutiplePathVariable() {
    let path = "/v{reallyLongVariable}/devices/{deviceId}/messages/{messageId}/payloads"
    let variables: Parameters = [
      "reallyLongVariable": 1,
      "deviceId": 123,
      "messageId": 456,
    ]

    let encodedPath = try! PathParameters.encode(path, with: variables)

    XCTAssert(encodedPath == "/v1/devices/123/messages/456/payloads")
  }
}
