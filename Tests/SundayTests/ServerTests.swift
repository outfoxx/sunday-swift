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

import PotentJSON
@testable import Sunday
@testable import SundayServer
import XCTest


struct Item: Codable, Equatable {
  let name: String
  let cost: Float
}


class HTTPServerTests: XCTestCase {

  static func buildAndStartServer() -> (URL, RoutingHTTPServer) {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/chunked") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.send(chunk: "12345".data(using: .utf8)!)
          res.send(chunk: "67890".data(using: .utf8)!)
          res.send(chunk: "12345".data(using: .utf8)!)
          res.send(chunk: "67890".data(using: .utf8)!)
          res.finish(trailers: [:])
        }
      }
      Path("/{type}") {
        ContentNegotiation {

          GET(.path("type")) { _, res, _ in
            res.send(status: .ok, value: [Item(name: "abc", cost: 12.80), Item(name: "def", cost: 6.40)])
          }

          POST(.path("type"), .body(Item.self)) { _, res, _, body in
            res.send(status: .created, value: body)
          }

          PUT(.path("type"), .body(Item.self)) { _, res, _, body in
            res.send(status: .created, value: body)
          }

          Path("/{id}") {

            GET(.path("id", Int.self)) { _, res, _ in
              res.send(status: .ok, value: Item(name: "abc", cost: 12.80))
            }

            DELETE(.path("id", Int.self)) { _, res, _ in
              res.send(status: .noContent)
            }
          }

        }
      }
    }

    guard let serverURL = server.start(timeout: 5.0) else {
      XCTFail("could not start local server")
      fatalError()
    }

    return (serverURL, server)
  }

  func testPOST() async throws {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "something", relativeTo: serverURL)!)
    urlRequest.httpMethod = "POST"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "content-type")
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")
    urlRequest.httpBody = try JSONEncoder.default.encode(Params(name: "ghi", cost: 19.20))

    let (data, response) = try await session.validatedData(for: urlRequest)

    XCTAssertNotNil(data)
    XCTAssertEqual(response.statusCode, 201)

    let item = try JSONDecoder.default.decode(Item.self, from: data ?? Data())
    XCTAssertEqual(item, Item(name: "ghi", cost: 19.20))
  }

  func testGETList() async throws {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    var urlRequest = URLRequest(url: URL(string: "something", relativeTo: serverURL)!)
    urlRequest.httpMethod = "GET"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let (data, response) = try await session.validatedData(for: urlRequest)

    XCTAssertNotNil(data)
    XCTAssertEqual(response.statusCode, 200)

    let items = try JSONDecoder.default.decode([Item].self, from: data ?? Data())
    XCTAssertTrue(items.contains(Item(name: "abc", cost: 12.80)))
    XCTAssertTrue(items.contains(Item(name: "def", cost: 6.40)))
  }

  func testGETItem() async throws {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    var urlRequest = URLRequest(url: URL(string: "something/123", relativeTo: serverURL)!)
    urlRequest.httpMethod = "GET"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let (data, response) = try await session.validatedData(for: urlRequest)

    XCTAssertNotNil(data)
    XCTAssertEqual(response.statusCode, 200)

    let item = try JSONDecoder.default.decode(Item.self, from: data ?? Data())
    XCTAssertEqual(item, Item(name: "abc", cost: 12.80))
  }

  func testDELETE() async throws {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    var urlRequest = URLRequest(url: URL(string: "something/123", relativeTo: serverURL)!)
    urlRequest.httpMethod = "DELETE"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let (data, response) = try await session.validatedData(for: urlRequest)

    XCTAssertNil(data)
    XCTAssertEqual(response.statusCode, 204)
  }

  func testPUTExpect() async throws {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "something", relativeTo: serverURL)!)
    urlRequest.httpMethod = "PUT"
    urlRequest.addValue("100-continue", forHTTPHeaderField: "expect")
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "content-type")
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")
    urlRequest.httpBody = try JSONEncoder.default.encode(Params(name: "ghi", cost: 19.20))

    let (data, response) = try await session.validatedData(for: urlRequest)

    XCTAssertNotNil(data)
    XCTAssertEqual(response.statusCode, 201)

    let item = try JSONDecoder.default.decode(Item.self, from: data ?? Data())
    XCTAssertEqual(item, Item(name: "ghi", cost: 19.20))
  }

  func testChunked() async throws {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "chunked", relativeTo: serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let (data, response) = try await session.validatedData(for: urlRequest)

    XCTAssertNotNil(data)
    XCTAssertEqual(response.statusCode, 200)

    XCTAssertEqual(data, "12345678901234567890".data(using: .utf8))
  }

}
