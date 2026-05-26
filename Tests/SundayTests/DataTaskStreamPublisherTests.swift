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

  var server: RoutingHTTPServer!

  override func tearDown() {
    server?.stop()
  }

  func testSimple() async throws {

    server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/regular") {
        GET { _, res in
          res.start(status: .ok, headers: [:])
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(500 * 0)) {
            res.send(body: Data(count: 1000), final: false)
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(500 * 2)) {
            res.send(body: Data(count: 1000), final: false)
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(500 * 4)) {
            res.send(body: Data(count: 1000), final: false)
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(500 * 6)) {
            res.send(body: Data(count: 1000), final: true)
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 30.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "regular", relativeTo: serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let dataStream = try session.dataEventStream(for: urlRequest)

    var didConnect = false
    var totalDataCount = 0
    for try await dataEvent in dataStream {
      switch dataEvent {
      case .connect(let response):
        XCTAssertEqual(response.statusCode, 200)
        didConnect = true

      case .data(let data):
        totalDataCount += data.count
      }
    }

    XCTAssertTrue(didConnect)
    XCTAssertEqual(totalDataCount, 4000)
  }

  func testChunked() async throws {

    let chunkGates = (0 ..< 4).map { _ in DispatchSemaphore(value: 0) }

    server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/chunked") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.send(chunk: Data(count: 1000))
          res.server.queue.async {
            for idx in 0 ..< 3 {
              chunkGates[idx].wait()
              res.send(chunk: Data(count: 1000))
            }

            chunkGates[3].wait()
            res.finish(trailers: [:])
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 30.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "chunked", relativeTo: serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let dataStream = try session.dataEventStream(for: urlRequest)

    var didConnect = false
    var totalDataCount = 0
    var completedChunks = 0
    var currentChunkDataCount = 0
    for try await dataEvent in dataStream {
      switch dataEvent {
      case .connect(let response):
        XCTAssertEqual(response.statusCode, 200)
        didConnect = true

      case .data(let data):
        totalDataCount += data.count
        currentChunkDataCount += data.count
        while currentChunkDataCount >= 1000, completedChunks < chunkGates.count {
          chunkGates[completedChunks].signal()
          completedChunks += 1
          currentChunkDataCount -= 1000
        }
      }
    }

    XCTAssertTrue(didConnect)
    XCTAssertEqual(totalDataCount, 4000)
    XCTAssertEqual(completedChunks, 4)
  }

  func testCompletesWithErrorWhenHTTPErrorResponse() async throws {

    server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/regular") {
        GET { _, res in
          res.send(status: .badRequest, text: "fix it")
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 30.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let urlRequest = URLRequest(url: URL(string: "regular", relativeTo: serverURL)!)

    let dataStream = try session.dataEventStream(for: urlRequest)

    do {
      for try await _ in dataStream {
        XCTFail("publisher emitted value, expected error")
      }
    }
    catch {
      guard
        case SundayError.responseValidationFailed(reason: let reason) = error,
        case ResponseValidationFailureReason.unacceptableStatusCode(response: _, data: _) = reason
      else {
        return XCTFail("published emitted unexpected error type")
      }
    }
  }


}
