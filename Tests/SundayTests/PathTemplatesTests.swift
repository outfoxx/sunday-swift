//
//  URITemplatesTests.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

@testable import Sunday
import XCTest


class URITemplatesTests: XCTestCase {

  func testMutiplePathVariable() {
    let pathTemplate = URI.Template(
      template: "http://example.com/v{reallyLongVariable}/devices/{deviceId}/messages/{messageId}/payloads",
      parameters: [
        "reallyLongVariable": 1,
        "deviceId": 123,
        "messageId": 456,
      ]
    )

    let encodedPath = try! pathTemplate.complete()

    XCTAssertEqual(encodedPath, URL(string: "http://example.com/v1/devices/123/messages/456/payloads"))
  }
}
