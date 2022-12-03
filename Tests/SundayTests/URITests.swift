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

@testable import Sunday
import XCTest


class URITests: XCTestCase {

  func testParseInit() throws {

    let uri = try URI(string: "http://example.com/api/v1/items?limit=10#block")

    XCTAssertEqual(uri.scheme, "http")
    XCTAssertEqual(uri.host, "example.com")
    XCTAssertEqual(uri.path, "/api/v1/items")
    XCTAssertEqual(uri.query, "limit=10")
    XCTAssertEqual(uri.queryItems, [URLQueryItem(name: "limit", value: "10")])
    XCTAssertEqual(uri.fragment, "block")
    XCTAssertEqual(uri.string, "http://example.com/api/v1/items?limit=10#block")
  }

  func testParseInitOpaque() throws {

    let uri = try URI(string: "mailto:test@example.com")

    XCTAssertEqual(uri.scheme, "mailto")
    XCTAssertEqual(uri.path, "test@example.com")
    XCTAssertEqual(uri.string, "mailto:test@example.com")
  }

  func testParseInitFailsWithBadURL() throws {

    XCTAssertThrowsError(try URI(string: "http://example host/api/v1/items?limit=10#block")) { error in
      guard let error = error as? URI.Error else {
        return XCTFail("unexpected error")
      }
      XCTAssertEqual(error, URI.Error.invalidURI)
    }

  }

  func testInit() throws {

    let uri = URI(
      scheme: "http",
      host: "example.com",
      path: "/api/v1/items",
      queryItems: [.init(name: "limit", value: "10")],
      fragment: "block"
    )

    XCTAssertEqual(uri.scheme, "http")
    XCTAssertEqual(uri.host, "example.com")
    XCTAssertEqual(uri.path, "/api/v1/items")
    XCTAssertEqual(uri.query, "limit=10")
    XCTAssertEqual(uri.queryItems, [URLQueryItem(name: "limit", value: "10")])
    XCTAssertEqual(uri.fragment, "block")
    XCTAssertEqual(uri.string, "http://example.com/api/v1/items?limit=10#block")
  }

  func testInitOpaque() throws {

    let uri = URI(scheme: "mailto", path: "test@example.com")

    XCTAssertEqual(uri.scheme, "mailto")
    XCTAssertEqual(uri.path, "test@example.com")
    XCTAssertEqual(uri.string, "mailto:test@example.com")
  }

  func testComponentsInit() throws {

    let components = URLComponents(string: "http://example.com/api/v1/items?limit=10#block")!
    let uri = URI(components: components)

    XCTAssertEqual(uri.scheme, components.scheme)
    XCTAssertEqual(uri.host, components.host)
    XCTAssertEqual(uri.path, components.path)
    XCTAssertEqual(uri.query, components.query)
    XCTAssertEqual(uri.queryItems, components.queryItems)
    XCTAssertEqual(uri.fragment, components.fragment)
  }

  func testCodable() throws {


    let uri = URI(
      scheme: "http",
      host: "example.com",
      path: "/api/v1/items",
      queryItems: [.init(name: "limit", value: "10")],
      fragment: "block"
    )

    let encoded = try JSONEncoder().encode(uri)
    let decoded = try JSONDecoder().decode(URI.self, from: encoded)

    XCTAssertEqual(decoded, uri)
  }

}
