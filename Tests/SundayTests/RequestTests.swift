//
//  RequestTests.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/28/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import XCTest
import Alamofire
import PromiseKit
import PotentCodables
@testable import Sunday
@testable import SundayServer


class RequestTests: ParameterizedTest {

  override class var parameterSets : [Any] {
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
          POST(.body(AnyValue.self)) { req, res, body in
            return res.send(status: .ok, value: body)
          }
        }
      }
    }
    XCTAssertTrue(server.start())

    let x = expectation(description: "echo repsonse")

    let sourceObject = TestObject(a: 1, b: 2.0, c: Date.millisecondDate(), d: "Hello", e: ["World"])

    let target = EndpointTarget(baseURL: "http://localhost:\(server.port)/")

    let reqMgr = NetworkRequestManager(target: target, sessionManager: .default)

    try reqMgr
      .fetch(method: .post, pathTemplate: "echo",
             pathParameters: nil, queryParameters: nil, body: sourceObject,
             contentType: contentType, acceptTypes: [acceptType], headers: nil)
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

struct TestObject : Codable, Equatable {
  let a: Int
  let b: Double
  let c: Date
  let d: String
  let e: [String]
}
