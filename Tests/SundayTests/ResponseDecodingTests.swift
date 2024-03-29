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

import PotentCodables
@testable import Sunday
@testable import SundayServer
import XCTest


class ResponseDecodingTests: XCTestCase {

  func testAdaptiveResponseDecodingJSONtoJSON() async throws {
    try await testAdaptiveResponseDecoding(contentType: .json, acceptType: .json)
  }

  func testAdaptiveResponseDecodingJSONtoCBOR() async throws {
    try await testAdaptiveResponseDecoding(contentType: .json, acceptType: .cbor)
  }

  func testAdaptiveResponseDecodingCBORtoJSON() async throws {
    try await testAdaptiveResponseDecoding(contentType: .cbor, acceptType: .json)
  }

  func testAdaptiveResponseDecodingCBORtoCBOR() async throws {
    try await testAdaptiveResponseDecoding(contentType: .cbor, acceptType: .cbor)
  }

  func testAdaptiveResponseDecoding(contentType: MediaType, acceptType: MediaType) async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/echo") {
          POST(.body(AnyValue.self)) { _, res, body in
            res.send(status: .ok, value: body)
          }
        }
      }
    }

    guard let url = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let sourceObject = TestObject(aaa: 1, bbb: 2.0, ccc: Date.millisecondDate(), ddd: "Hello", eee: ["World"])

    let baseURL = URI.Template(format: url.absoluteString)

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let returnedObject =
      try await requestFactory.result(
        method: .post,
        pathTemplate: "echo",
        pathParameters: nil,
        queryParameters: nil,
        body: sourceObject,
        contentTypes: [contentType],
        acceptTypes: [acceptType],
        headers: nil
      ) as TestObject

    XCTAssertEqual(sourceObject, returnedObject)
  }

}

struct TestObject: Codable, Equatable {
  let aaa: Int
  let bbb: Double
  let ccc: Date
  let ddd: String
  let eee: [String]
}
