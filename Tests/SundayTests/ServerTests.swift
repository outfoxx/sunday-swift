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

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      fatalError()
    }

    return (serverURL, server)
  }

  func testPOST() throws {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let postCompleteX = expectation(description: "POST - complete")
    let postDataX = expectation(description: "POST - data")

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "something", relativeTo: serverURL)!)
    urlRequest.httpMethod = "POST"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "content-type")
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")
    urlRequest.httpBody = try JSONEncoder.default.encode(Params(name: "ghi", cost: 19.20))

    let requestCancel = session.dataTaskValidatedPublisher(request: urlRequest)
      .sink(
        receiveCompletion: { completion in
          defer { postCompleteX.fulfill() }

          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
        },
        receiveValue: { response, data in
          defer { postDataX.fulfill() }

          guard let data = data else {
            XCTFail("No response data")
            return
          }

          guard response.statusCode == 201 else {
            let message = String(data: data, encoding: .utf8)!
            XCTFail("Invalid response status code: \(response.statusCode) - \(message)")
            return
          }

          do {
            let item = try JSONDecoder.default.decode(Item.self, from: data)
            XCTAssertEqual(item, Item(name: "ghi", cost: 19.20))
          }
          catch {
            XCTFail("Decode/Compare failed: \(error)")
          }

        }
      )

    waitForExpectations { _ in
      requestCancel.cancel()
    }
  }

  func testGETList() {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let listCompleteX = expectation(description: "GET (list) - complete")
    let listDataX = expectation(description: "GET (list) - data")

    var urlRequest = URLRequest(url: URL(string: "something", relativeTo: serverURL)!)
    urlRequest.httpMethod = "GET"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let requestCancel = session.dataTaskValidatedPublisher(request: urlRequest)
      .sink(
        receiveCompletion: { completion in
          defer { listCompleteX.fulfill() }

          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
        },
        receiveValue: { response, data in
          defer { listDataX.fulfill() }

          guard let data = data else {
            XCTFail("No response data")
            return
          }

          guard response.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)!
            XCTFail("Invalid response status code: \(response.statusCode) - \(message)")
            return
          }

          do {
            let items = try JSONDecoder.default.decode([Item].self, from: data)
            XCTAssertTrue(items.contains(Item(name: "abc", cost: 12.80)))
            XCTAssertTrue(items.contains(Item(name: "def", cost: 6.40)))
          }
          catch {
            XCTFail("Decode/Compare failed: \(error)")
          }

        }
      )

    waitForExpectations { _ in
      requestCancel.cancel()
    }
  }

  func testGETItem() {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let itemCompleteX = expectation(description: "GET (item) - complete")
    let itemDataX = expectation(description: "GET (item) - data")

    var urlRequest = URLRequest(url: URL(string: "something/123", relativeTo: serverURL)!)
    urlRequest.httpMethod = "GET"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let requestCancel = session.dataTaskValidatedPublisher(request: urlRequest)
      .sink(
        receiveCompletion: { completion in
          defer { itemCompleteX.fulfill() }

          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
        },
        receiveValue: { response, data in
          defer { itemDataX.fulfill() }

          guard let data = data else {
            XCTFail("No response data")
            return
          }

          guard response.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)!
            XCTFail("Invalid response status code: \(response.statusCode) - \(message)")
            return
          }

          do {
            let item = try JSONDecoder.default.decode(Item.self, from: data)
            XCTAssertEqual(item, Item(name: "abc", cost: 12.80))
          }
          catch {
            XCTFail("Decode/Compare failed: \(error)")
          }

        }
      )

    waitForExpectations { _ in
      requestCancel.cancel()
    }
  }

  func testDELETE() {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let deleteCompleteX = expectation(description: "DELETE - complete")
    let deleteDataX = expectation(description: "DELETE - data")

    var urlRequest = URLRequest(url: URL(string: "something/123", relativeTo: serverURL)!)
    urlRequest.httpMethod = "DELETE"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let requestCancel = session.dataTaskValidatedPublisher(request: urlRequest)
      .sink(
        receiveCompletion: { completion in
          defer { deleteCompleteX.fulfill() }

          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
        },
        receiveValue: { response, data in
          defer { deleteDataX.fulfill() }

          guard let data = data else {
            XCTFail("No response data")
            return
          }

          guard response.statusCode == 204 else {
            let message = String(data: data, encoding: .utf8)!
            XCTFail("Invalid response status code: \(response.statusCode) - \(message)")
            return
          }

          XCTAssertEqual(data.count, 0)

        }
      )

    waitForExpectations { _ in
      requestCancel.cancel()
    }
  }

  func testPUTExpect() throws {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let putCompleteX = expectation(description: "PUT - complete")
    let putDataX = expectation(description: "PUT - data")

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

    let requestCancel = session.dataTaskValidatedPublisher(request: urlRequest)
      .sink(
        receiveCompletion: { completion in
          defer { putCompleteX.fulfill() }

          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
        },
        receiveValue: { response, data in
          defer { putDataX.fulfill() }

          guard let data = data else {
            XCTFail("No response data")
            return
          }

          guard response.statusCode == 201 else {
            let message = String(data: data, encoding: .utf8)!
            XCTFail("Invalid response status code: \(response.statusCode) - \(message)")
            return
          }

          do {
            let item = try JSONDecoder.default.decode(Item.self, from: data)
            XCTAssertEqual(item, Item(name: "ghi", cost: 19.20))
          }
          catch {
            XCTFail("Decode/Compare failed: \(error)")
          }

        }
      )

    waitForExpectations { _ in
      requestCancel.cancel()
    }
  }

  func testChunked() {

    let (serverURL, server) = Self.buildAndStartServer()
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let getChunkedCompleteX = expectation(description: "GET (chunked) - complete")
    let getChunkedDataX = expectation(description: "GET (chunked) - data")

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "chunked", relativeTo: serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    let requestCancel = session.dataTaskValidatedPublisher(request: urlRequest)
      .sink(
        receiveCompletion: { completion in
          defer { getChunkedCompleteX.fulfill() }

          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
        },
        receiveValue: { response, data in
          defer { getChunkedDataX.fulfill() }

          guard let data = data else {
            XCTFail("No response data")
            return
          }

          guard response.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)!
            XCTFail("Invalid response status code: \(response.statusCode) - \(message)")
            return
          }

          XCTAssertEqual(data, "12345678901234567890".data(using: .utf8))
        }
      )

    waitForExpectations { _ in
      requestCancel.cancel()
    }

  }

}
