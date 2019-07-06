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


struct Item : Codable {
  let name: String
  let cost: Decimal
}


@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
class HTTPServerTests: XCTestCase {

  func testRoutableServer() throws {

    let server = try HTTPServer(port: .any) {
      Path("/{type}") {
        ContentNegotiation {

          GET(.path("type")) { type -> HTTP.Response in
            .ok(value: [Item(name: "abc", cost: 12.80), Item(name: "def", cost: 6.40)])
          }

          POST(.path("type"), .body(Item.self)) { type, body -> HTTP.Response in
            .ok(value: body)
          }

          Path("{id}") {

            GET(.path("id", Int.self)) { id -> HTTP.Response in
              .ok(value: Item(name: "abc", cost: 12.80))
            }

          }

        }
      }
    }

    Thread.sleep(forTimeInterval: 0.5)

    let x = expectation(description: "Completed")
    SessionManager.default.request("http://localhost:\(server.port)/something", method: .post, parameters: ["name": "abc", "cost": 12.40],
                                   encoding: JSONEncoding.default, headers: ["Accept": "application/json"])
//      .validate()
      .response { (response) in
        defer { x.fulfill() }

        guard response.error == nil else {
          XCTFail("Request failed: \(response.error!)")
          return
        }

        print("Response - ", String(data: response.data!, encoding: .utf8)!)
      }

    waitForExpectations(timeout: 10)
  }

}
