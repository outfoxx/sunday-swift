//
//  PathParametersTests.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/28/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import XCTest
import Alamofire
@testable import Sunday


class PathParametersTest: XCTestCase {

  func testMutiplePathVariable() {
    let path = "/v{reallyLongVariable}/devices/{deviceId}/messages/{messageId}/payloads"
    let variables: Parameters = [
      "reallyLongVariable": 1,
      "deviceId": 123,
      "messageId": 456
    ]

    let encodedPath = try! PathParameters.encode(path, with: variables)

    XCTAssert(encodedPath == "/v1/devices/123/messages/456/payloads")
  }
}
