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
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 0)) {
            res.send(body: Data(count: 1000), final: false)
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 1)) {
            res.send(body: Data(count: 1000), final: false)
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 2)) {
            res.send(body: Data(count: 1000), final: false)
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 3)) {
            res.send(body: Data(count: 1000), final: true)
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "regular", relativeTo: serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let dataStream = try session.dataEventStream(for: urlRequest)

    var eventCount = 0
    for try await dataEvent in dataStream {
      switch dataEvent {
      case .connect(let response):
        XCTAssertEqual(response.statusCode, 200)

      case .data(let data):
        XCTAssertEqual(data.count, 1000)
      }
      eventCount += 1
    }

    XCTAssertEqual(eventCount, 5)
  }

  func testChunked() async throws {

    server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/chunked") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 0)) {
            res.send(chunk: Data(count: 1000))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 1)) {
            res.send(chunk: Data(count: 1000))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 2)) {
            res.send(chunk: Data(count: 1000))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 3)) {
            res.send(chunk: Data(count: 1000))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(250 * 4)) {
            res.finish(trailers: [:])
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "chunked", relativeTo: serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let dataStream = try session.dataEventStream(for: urlRequest)

    var eventCount = 0
    for try await dataEvent in dataStream {
      switch dataEvent {
      case .connect(let response):
        print("## EVENT: connect")
        XCTAssertEqual(response.statusCode, 200)

      case .data(let data):
        print("## EVENT: data")
        XCTAssertEqual(data.count, 1000)
      }
      eventCount += 1
    }

    XCTAssertEqual(eventCount, 5)
  }

  func testCompletesWithErrorWhenHTTPErrorResponse() async throws {

    server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/regular") {
        GET { _, res in
          res.send(status: .badRequest, text: "fix it")
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
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
