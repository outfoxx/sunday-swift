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

    let completeX = expectation(description: "echo repsonse - complete")
    let dataX = expectation(description: "echo repsonse - data")

    let sourceObject = TestObject(a: 1, b: 2.0, c: Date.millisecondDate(), d: "Hello", e: ["World"])

    let baseURL = URLTemplate(template: url!.absoluteString)

    let reqMgr = NetworkRequestManager(baseURL: baseURL)

    let requestCancel =
      reqMgr.result(method: .post, pathTemplate: "echo",
                    pathParameters: nil, queryParameters: nil, body: sourceObject,
                    contentTypes: [contentType], acceptTypes: [acceptType], headers: nil)
      .sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
          completeX.fulfill()
        },
        receiveValue: { (returnedObject: TestObject) in
          XCTAssertEqual(sourceObject, returnedObject)
          dataX.fulfill()
        }
      )

    waitForExpectations(timeout: 5.0) { _ in
      requestCancel.cancel()
    }
  }

}

struct TestObject: Codable, Equatable {
  let a: Int
  let b: Double
  let c: Date
  let d: String
  let e: [String]
}
