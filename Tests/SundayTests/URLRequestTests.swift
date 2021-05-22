//
//  URLRequestTests.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation

@testable import Sunday
import XCTest


class URLRequestTests: XCTestCase {

  func testFluent() {

    let req = URLRequest(url: URL(string: "http://example.com")!)

    XCTAssertEqual(req.with(httpMethod: .connect).httpMethod, "CONNECT")
    XCTAssertEqual(req.with(httpBody: "test".data(using: .utf8)).httpBody, "test".data(using: .utf8))

    let stream = InputStream(data: Data(count: 100))
    XCTAssertEqual(req.with(httpBody: stream).httpBodyStream, stream)
    XCTAssertEqual(req.with(timeoutInterval: 10.0).timeoutInterval, 10.0)
    XCTAssertEqual(req.adding(httpHeaders: ["test": ["1"]]).value(forHTTPHeaderField: "test"), "1")
  }

}
