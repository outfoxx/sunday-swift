//
//  File.swift
//  
//
//  Created by Kevin Wooten on 8/5/20.
//

import Foundation
import XCTest
import Sunday
import SundayServer

@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
class EventSourceTests: XCTestCase {
  
  static let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
    Path("/simple") {
      GET { _, res in
        res.start(status: .ok, headers: [
          HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
          HTTP.StdHeaders.transferEncoding: ["chunked"]
        ])
        res.send(chunk: "event: test\n".data(using: .utf8)!)
        res.send(chunk: "id: 123\n".data(using: .utf8)!)
        res.send(chunk: "data: some test data\n\n".data(using: .utf8)!)
        res.finish(trailers: [:])
      }
    }
    Path("/json") {
      GET { _, res in
        res.start(status: .ok, headers: [
          HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
          HTTP.StdHeaders.transferEncoding: ["chunked"]
        ])
        res.send(chunk: "event: test\n".data(using: .utf8)!)
        res.send(chunk: "id: 123\n".data(using: .utf8)!)
        res.send(chunk: "data: {\"some\":\r".data(using: .utf8)!)
        res.send(chunk: "data: \"test data\"}\n\n".data(using: .utf8)!)
        res.finish(trailers: [:])
      }
    }
    CatchAll { route, req, res in
      print(route)
      print(req)
    }
  }
  static var serverURL: URL!

  let session = URLSession.create(configuration: .default)

  override class func setUp() {
    super.setUp()
    
    serverURL = server.start()
    XCTAssertNotNil(serverURL)
  }
  
  func testSimpleData() throws {
    let eventSource = EventSource { self.session.dataStream(request: URLRequest(url: URL(string: "/simple", relativeTo: Self.serverURL)!).adding(httpHeaders: $0)) }
    
    let x = expectation(description: "Event Received")
    eventSource.onMessage { (id, event, data) in
      XCTAssertEqual(id, "123")
      XCTAssertEqual(event, "test")
      XCTAssertEqual(data, "some test data")
      x.fulfill()
    }
    eventSource.connect()
    
    waitForExpectations(timeout: 1.0, handler: nil)
  }
  
  func testJSONData() throws {
    let eventSource = EventSource { self.session.dataStream(request: URLRequest(url: URL(string: "/json", relativeTo: Self.serverURL)!).adding(httpHeaders: $0)) }
    
    let x = expectation(description: "Event Received")
    eventSource.onMessage { (id, event, data) in
      XCTAssertEqual(id, "123")
      XCTAssertEqual(event, "test")
      XCTAssertEqual(data, "{\"some\":\n\"test data\"}")
      x.fulfill()
    }
    eventSource.connect()
    
    waitForExpectations(timeout: 1.0, handler: nil)
  }

}
