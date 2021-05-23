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
import Sunday
import SundayServer
import XCTest


class DataTaskStreamPublisherTests: XCTestCase {

  func testSimple() {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/regular") {
        GET { _, res in
          res.start(status: .ok, headers: [:])
          res.send(body: Data(count: 1000), final: false)
          Thread.sleep(forTimeInterval: 0.1)
          res.send(body: Data(count: 1000), final: false)
          Thread.sleep(forTimeInterval: 0.1)
          res.send(body: Data(count: 1000), final: false)
          Thread.sleep(forTimeInterval: 0.1)
          res.send(body: Data(count: 1000), final: true)
        }
      }
    }
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let getChunkedCompleteX = expectation(description: "GET - complete")
    let getChunkedDataX = expectation(description: "GET - data")
    getChunkedDataX.expectedFulfillmentCount = 5

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "regular", relativeTo: serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let requestCancel = session.dataTaskStreamPublisher(for: urlRequest)
      .sink { completion in
        defer { getChunkedCompleteX.fulfill() }

        if case .failure(let error) = completion {
          XCTFail("Request failed: \(error)")
        }

      } receiveValue: { event in
        defer { getChunkedDataX.fulfill() }

        switch event {
        case .connect(let response):
          XCTAssertEqual(response.statusCode, 200)

        case .data(let data):
          XCTAssertEqual(data.count, 1000)
        }
      }

    waitForExpectations { _ in
      requestCancel.cancel()
    }

  }

  func testChunked() {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/chunked") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.send(chunk: Data(count: 1000))
          Thread.sleep(forTimeInterval: 0.1)
          res.send(chunk: Data(count: 1000))
          Thread.sleep(forTimeInterval: 0.1)
          res.send(chunk: Data(count: 1000))
          Thread.sleep(forTimeInterval: 0.1)
          res.send(chunk: Data(count: 1000))
          res.finish(trailers: [:])
        }
      }
    }
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let getChunkedCompleteX = expectation(description: "GET (chunked) - complete")
    let getChunkedDataX = expectation(description: "GET (chunked) - data")
    getChunkedDataX.expectedFulfillmentCount = 5

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "chunked", relativeTo: serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let requestCancel = session.dataTaskStreamPublisher(for: urlRequest)
      .sink(
        receiveCompletion: { completion in
          defer { getChunkedCompleteX.fulfill() }

          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
        },
        receiveValue: { event in
          defer { getChunkedDataX.fulfill() }

          switch event {
          case .connect(let response):
            XCTAssertEqual(response.statusCode, 200)

          case .data(let data):
            XCTAssertEqual(data.count, 1000)
          }
        }
      )

    waitForExpectations { _ in
      requestCancel.cancel()
    }

  }

  func testCompletesWithErrorWhenHTTPErrorResponse() {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/regular") {
        GET { _, res in
          res.send(status: .badRequest, text: "fix it")
        }
      }
    }
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let completeX = expectation(description: "received error")

    let urlRequest = URLRequest(url: URL(string: "regular", relativeTo: serverURL)!)

    let requestCancel = session.dataTaskStreamPublisher(for: urlRequest)
      .sink { completion in
        defer { completeX.fulfill() }

        guard case .failure(let error) = completion else {
          return XCTFail("publisher completed, expected error")
        }

        guard
          case SundayError.responseValidationFailed(reason: let reason) = error,
          case ResponseValidationFailureReason.unacceptableStatusCode(response: _, data: _) = reason
        else {
          return XCTFail("published emitted unexpected error type")
        }

      } receiveValue: { _ in
        XCTFail("publisher emitted value, expected error")
      }

    waitForExpectations { _ in
      requestCancel.cancel()
    }

  }


}
