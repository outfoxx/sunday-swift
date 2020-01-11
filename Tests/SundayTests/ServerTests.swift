//
//  ServerTests.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import PotentJSON
@testable import Sunday
@testable import SundayServer
import XCTest


struct Item: Codable, Equatable {
  let name: String
  let cost: Float
}


@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
class HTTPServerTests: XCTestCase {

  static let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
    Path("/{type}") {
      ContentNegotiation {

        GET(.path("type")) { _, res, _ in
          res.send(status: .ok, value: [Item(name: "abc", cost: 12.80), Item(name: "def", cost: 6.40)])
        }

        POST(.path("type"), .body(Item.self)) { _, res, _, body in
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
  static var serverURL: URL!

  let session = URLSession.create(configuration: .default)

  override class func setUp() {
    super.setUp()

    serverURL = server.start()
    XCTAssertNotNil(serverURL)
  }

  func testPOST() throws {

    let postX = expectation(description: "POST")

    struct Params: Codable {
      let name: String
      let cost: Double
    }

    var urlRequest = URLRequest(url: URL(string: "something", relativeTo: HTTPServerTests.serverURL)!)
    urlRequest.httpMethod = "POST"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "content-type")
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")
    urlRequest.httpBody = try JSONEncoder.default.encode(Params(name: "ghi", cost: 19.20))

    _ = session.response(request: urlRequest)
      .subscribe(
        onSuccess: { (response, data) in
          defer { postX.fulfill() }

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
        },
        onError: { error in
          defer { postX.fulfill() }
          XCTFail("Request failed: \(error)")
        }
      )

    waitForExpectations(timeout: 2)
  }

  func testGETList() {

    let listX = expectation(description: "GET (list)")

    var urlRequest = URLRequest(url: URL(string: "something", relativeTo: HTTPServerTests.serverURL)!)
    urlRequest.httpMethod = "GET"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    _ = session.response(request: urlRequest)
      .subscribe(
        onSuccess: { (response, data) in
          defer { listX.fulfill() }

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
        },
        onError: { error in
          defer { listX.fulfill() }
          XCTFail("Request failed: \(error)")
        }
      )

    waitForExpectations(timeout: 2)
  }

  func testGETItem() {

    let itemX = expectation(description: "GET (item)")

    var urlRequest = URLRequest(url: URL(string: "something/123", relativeTo: HTTPServerTests.serverURL)!)
    urlRequest.httpMethod = "GET"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    _ = session.response(request: urlRequest)
      .subscribe(
        onSuccess: { (response, data) in
          defer { itemX.fulfill() }

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
        },
        onError: { error in
          defer { itemX.fulfill() }
          XCTFail("Request failed: \(error)")
        }
      )

    waitForExpectations(timeout: 2)
  }

  func testDELETE() {

    let deleteX = expectation(description: "DELETE")

    var urlRequest = URLRequest(url: URL(string: "something/123", relativeTo: HTTPServerTests.serverURL)!)
    urlRequest.httpMethod = "DELETE"
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")

    _ = session.response(request: urlRequest)
      .subscribe(
        onSuccess: { (response, data) in
          defer { deleteX.fulfill() }

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
        },
        onError: { error in
          defer { deleteX.fulfill() }
          XCTFail("Request failed: \(error)")
        }
      )

    waitForExpectations(timeout: 2)
  }

  func testChunked() {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/chunked") {
          PUT(.body()) { _, _, _ in

          }
        }
      }
    }

  }

}
