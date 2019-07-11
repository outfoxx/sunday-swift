//
//  HTTPServerTests.swift
//  
//
//  Created by Kevin Wooten on 7/5/19.
//

import XCTest
import Alamofire
import class PotentCodables.JSONDecoder
@testable import Sunday
@testable import SundayServer


struct Item : Codable, Equatable {
  let name: String
  let cost: Float
}


@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
class HTTPServerTests: XCTestCase {

  static let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
    Path("/{type}") {
      ContentNegotiation {

        GET(.path("type")) { type in
          .ok(value: [Item(name: "abc", cost: 12.80), Item(name: "def", cost: 6.40)])
        }

        POST(.path("type"), .body(Item.self)) { type, body in
          .created(value: body)
        }

        Path("{id}") {

          GET(.path("id", Int.self)) { id in
            .ok(value: Item(name: "abc", cost: 12.80))
          }

          DELETE(.path("id", Int.self)) { id in
            .noContent()
          }
        }

      }
    }
  }

  override class func setUp() {
    super.setUp()

    XCTAssertTrue(server.start())
  }

  func testPOST() throws {

    let postX = expectation(description: "POST")
    SessionManager.default.request("http://localhost:\(Self.server.port)/something", method: .post,
                                   parameters: ["name": "ghi", "cost": 19.20],
                                   encoding: JSONEncoding.default, headers: ["Accept": "application/json"])
      .response { (response) in
        defer { postX.fulfill() }

        guard response.error == nil else {
          XCTFail("Request failed: \(response.error!)")
          return
        }

        guard let data = response.data else {
          XCTFail("No response data")
          return
        }

        guard response.response?.statusCode == 201 else {
          let message = String(data: data, encoding: .utf8)!
          XCTFail("Invalid response status code: \(response.response!.statusCode) - \(message)")
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

    waitForExpectations(timeout: 2)
  }

  func testGETList() {

    let listX = expectation(description: "GET (list)")
    SessionManager.default.request("http://localhost:\(Self.server.port)/something", method: .get,
                                   headers: ["Accept": "application/json"])
      .response { (response) in
        defer { listX.fulfill() }

        guard response.error == nil else {
          XCTFail("Request failed: \(response.error!)")
          return
        }

        guard let data = response.data else {
          XCTFail("No response data")
          return
        }

        guard response.response?.statusCode == 200 else {
          let message = String(data: data, encoding: .utf8)!
          XCTFail("Invalid response status code: \(response.response!.statusCode) - \(message)")
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

    waitForExpectations(timeout: 2)
  }

  func testGETItem() {

    let itemX = expectation(description: "GET (item)")
    SessionManager.default.request("http://localhost:\(Self.server.port)/something/123", method: .get,
                                   headers: ["Accept": "application/json"])
      .response { (response) in
        defer { itemX.fulfill() }

        guard response.error == nil else {
          XCTFail("Request failed: \(response.error!)")
          return
        }

        guard let data = response.data else {
          XCTFail("No response data")
          return
        }

        guard response.response?.statusCode == 200 else {
          let message = String(data: data, encoding: .utf8)!
          XCTFail("Invalid response status code: \(response.response!.statusCode) - \(message)")
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

    waitForExpectations(timeout: 2)
  }

  func testDELETE() {

    let deleteX = expectation(description: "DELETE")
    SessionManager.default.request("http://localhost:\(Self.server.port)/something/123", method: .delete)
      .response { (response) in
        defer { deleteX.fulfill() }

        guard response.error == nil else {
          XCTFail("Request failed: \(response.error!)")
          return
        }

        guard let data = response.data else {
          XCTFail("No response data")
          return
        }

        guard response.response?.statusCode == 204 else {
          let message = String(data: data, encoding: .utf8)!
          XCTFail("Invalid response status code: \(response.response!.statusCode) - \(message)")
          return
        }

        XCTAssertEqual(data.count, 0)
    }

    waitForExpectations(timeout: 2)
  }

}
