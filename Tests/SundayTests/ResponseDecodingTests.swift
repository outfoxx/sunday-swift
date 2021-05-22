//
//  ResponseDecodingTests.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import PotentCodables
@testable import Sunday
@testable import SundayServer
import XCTest


class ResponseDecodingTests: ParameterizedTest {

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

    guard let url = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let completeX = expectation(description: "echo repsonse - complete")
    let dataX = expectation(description: "echo repsonse - data")

    let sourceObject = TestObject(aaa: 1, bbb: 2.0, ccc: Date.millisecondDate(), ddd: "Hello", eee: ["World"])

    let baseURL = URI.Template(format: url.absoluteString)

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let requestCancel =
      requestFactory.result(
        method: .post,
        pathTemplate: "echo",
        pathParameters: nil,
        queryParameters: nil,
        body: sourceObject,
        contentTypes: [contentType],
        acceptTypes: [acceptType],
        headers: nil
      )
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
  let aaa: Int
  let bbb: Double
  let ccc: Date
  let ddd: String
  let eee: [String]
}
