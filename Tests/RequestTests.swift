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
import Embassy
import Ambassador
import PotentCodables
@testable import Sunday


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

  func testAdaptiveResponseDecoding() throws {

    let testServerManager = TestServerManager()
    testServerManager.start()

    let x = expectation(description: "echo repsonse")

    let sourceObject = TestObject(a: 1, b: 2.0, c: Date.millisecondDate(), d: "Hello", e: ["World"])

    let target = EndpointTarget(baseURL: "http://localhost:\(testServerManager.server.listenAddress.port)/")

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


private class TestServerManager {

  let loop = try! SelectorEventLoop(selector: try! KqueueSelector())

  let router = Router()

  let server: DefaultHTTPServer

  static let decoders = MediaTypeDecoders.Builder().registerDefault().build()
  static let encoders = MediaTypeEncoders.Builder().registerDefault().build()

  init() {

    router["^/echo$"] = SWGIWebApp { environ, start, send in

      var data = Data()

      let input = environ["swsgi.input"] as! SWSGIInput
      input { newData in

        guard newData.isEmpty else {
          data.append(newData)
          return
        }

        let contentType = MediaType((environ["HTTP_CONTENT_TYPE"] as! String))!
        let content = try! TestServerManager.decoders.find(for: contentType).decode(AnyValue.self, from: data)

        let acceptMediaType = (environ["HTTP_ACCEPT"] as! String).components(separatedBy: ",").first.map { MediaType($0)! } ?? .json
        let responseData = try! TestServerManager.encoders.find(for: acceptMediaType).encode(content)

        start("200 OK", [
          ("Content-Type", acceptMediaType.value),
          ("Content-Length", String(responseData.count))
        ])

        send(responseData)
      }

    }

    server = DefaultHTTPServer(eventLoop: loop, interface: "::", port: 0, app: router.app)
  }

  func start() {

    try! server.start()

    DispatchQueue.global(qos: .background).async {
      self.loop.runForever()
    }

  }

  func stop() {
    server.stopAndWait()
    loop.stop()
  }

}

