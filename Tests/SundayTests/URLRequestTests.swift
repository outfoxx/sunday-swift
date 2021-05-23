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
