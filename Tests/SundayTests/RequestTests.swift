//
//  RequestTests.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import PotentCodables
import PromiseKit
@testable import Sunday
@testable import SundayServer
import XCTest


class RequestTests: ParameterizedTest {

  override class var parameterSets: [Any] {
    return [
      (MediaType.json, MediaType.json),
      (MediaType.json, MediaType.cbor),
      (MediaType.cbor, MediaType.json),
      (MediaType.cbor, MediaType.cbor),
    ]
  }

  private var contentType = MediaType.cbor
  private var acceptType = MediaType.cbor

  override func setUp(with parameters: Any) {
    let (contentType, acceptType) = parameters as! (MediaType, MediaType)
    self.contentType = contentType
    self.acceptType = acceptType
  }

  @available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
  func testAdaptiveResponseDecoding() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/echo") {
          POST(.body(AnyValue.self)) { _, res, body in
            res.send(status: .ok, value: body)
          }
        }
      }
    }

    let url = server.start()
    XCTAssertNotNil(url)

    let x = expectation(description: "echo repsonse")

    let sourceObject = TestObject(a: 1, b: 2.0, c: Date.millisecondDate(), d: "Hello", e: ["World"])

    let baseURL = URLTemplate(template: url!.absoluteString)

    let reqMgr = NetworkRequestManager(baseURL: baseURL)

    try reqMgr
      .result(method: .post, pathTemplate: "echo",
              pathParameters: nil, queryParameters: nil, body: sourceObject,
              contentTypes: [contentType], acceptTypes: [acceptType], headers: nil)
      .promise()
      .done { (returnedObject: TestObject) in
        XCTAssertEqual(sourceObject, returnedObject)
      }
      .catch { error in
        XCTFail("Request failed: \(error)")
      }
      .finally {
        x.fulfill()
      }

    waitForExpectations(timeout: 500.0, handler: nil)
  }

}

struct TestObject: Codable, Equatable {
  let a: Int
  let b: Double
  let c: Date
  let d: String
  let e: [String]
}
