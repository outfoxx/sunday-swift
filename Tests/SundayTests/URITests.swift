//
//  URITests.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

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
  }
  
  func testParseInitFailsWithBadURL() throws {
    
    XCTAssertThrowsError(try URI(string: "http:\\example-host/api/v1/items?limit=10#block")) { error in
      guard let error = error as? URI.Error else {
        return XCTFail("unexpected error")
      }
      XCTAssertEqual(error, URI.Error.invalidURI)
    }
    
  }

  func testInit() throws {
    
    let uri = URI(scheme: "http", host: "example.com", path: "/api/v1/items",
                           queryItems: [.init(name: "limit", value: "10")], fragment: "block")
    
    XCTAssertEqual(uri.scheme, "http")
    XCTAssertEqual(uri.host, "example.com")
    XCTAssertEqual(uri.path, "/api/v1/items")
    XCTAssertEqual(uri.query, "limit=10")
    XCTAssertEqual(uri.queryItems, [URLQueryItem(name: "limit", value: "10")])
    XCTAssertEqual(uri.fragment, "block")
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
    
    
    let uri = URI(scheme: "http", host: "example.com", path: "/api/v1/items",
                  queryItems: [.init(name: "limit", value: "10")], fragment: "block")

    let encoded = try JSONEncoder().encode(uri)
    let decoded = try JSONDecoder().decode(URI.self, from: encoded)
    
    XCTAssertEqual(decoded, uri)
  }
  
}
