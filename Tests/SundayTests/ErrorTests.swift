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

import Sunday
import XCTest

final class ErrorTests: XCTestCase {

  func testDescriptions() throws {
    XCTAssertEqual(SundayError.unexpectedEmptyResponse.errorDescription, "Unexpected Empty Response")
    XCTAssertEqual(
      SundayError.invalidURL(URLComponents(string: "http://example.com")).errorDescription,
      "Invalid URL url=http://example.com"
    )
    XCTAssertEqual(SundayError.invalidHTTPResponse.errorDescription, "Invalid HTTP Response")
    XCTAssertEqual(
      RequestEncodingFailureReason.unsupportedContentType(.json).description,
      "Unsupported Content-Type: type=application/json"
    )
    XCTAssertEqual(
      ResponseDecodingFailureReason.unsupportedContentType(.json).description,
      "Unsupported Content-Type: type=application/json"
    )

    let response = HTTPURLResponse(url: URL(string: "http://example.com")!,
                                   mimeType: nil,
                                   expectedContentLength: 0,
                                   textEncodingName: nil)
    XCTAssertEqual(
      ResponseValidationFailureReason.unacceptableStatusCode(response: response, data: nil).description,
      "Unacceptable Status Code: status=200, url=http://example.com, response-size=empty"
    )
  }

}
