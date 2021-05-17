//
//  EventSourceTests.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import XCTest
import Sunday
import SundayServer


class EventSourceTests: XCTestCase {

  func testSimpleData() throws {
    
    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
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
      CatchAll { route, req, res in
        print(route)
        print(req)
      }
    }
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }
    
    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }
    
    let eventSource =
      EventSource {
        let request = URLRequest(url: URL(string: "/simple", relativeTo: serverURL)!).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }
    
    let messageX = expectation(description: "Event Received")
    
    eventSource.onMessage { (id, event, data) in
      eventSource.close()
      XCTAssertEqual(id, "123")
      XCTAssertEqual(event, "test")
      XCTAssertEqual(data, "some test data")
      messageX.fulfill()
    }
    
    eventSource.connect()
    
    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testJSONData() throws {
    
    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
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
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }
    
    let eventSource =
      EventSource {
        let request = URLRequest(url: URL(string: "/json", relativeTo: serverURL)!).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }
    
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

  func testCallbacks() throws {
    
    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        TrackInvocations(name: "invocations") {
          GET { _, res in
            
            // Send event for first request, fail after  that
            
            let invocations = res.properties["invocations"] as! Int
            if invocations == 0 {
              
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
            else {
              
              res.send(status: .badRequest, text: "fix it")
            }
            
          }
        }
      }
      CatchAll { route, req, res in
        print(route)
        print(req)
      }
    }
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }
    
    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }
    
    let eventSource =
      EventSource {
        let request = URLRequest(url: URL(string: "/simple", relativeTo: serverURL)!).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }
    
    let openX = expectation(description: "Open Received")
    let messageX = expectation(description: "Message Received")
    let listenerX = expectation(description: "Listener Received")
    let errorX = expectation(description: "Error Received")
    errorX.assertForOverFulfill = false
    
    eventSource.onOpen { openX.fulfill() }
    
    eventSource.onMessage { _, _, _ in  messageX.fulfill() }
    
    eventSource.addEventListener("test") { (id, event, data) in
      listenerX.fulfill()
    }

    eventSource.onError { _ in
      eventSource.close()
      errorX.fulfill()
    }
    
    eventSource.connect()
    
    waitForExpectations(timeout: 2.0, handler: nil)
  }

  func testEventListenerRemove() throws {

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }
    
    let eventSource =
      EventSource {
        let request = URLRequest(url: URL(string: "http://example.com/simple")!).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }


    eventSource.addEventListener("test") { _, _, _ in }
    XCTAssertTrue(!eventSource.events().isEmpty)

    eventSource.removeEventListener("test")
    XCTAssertTrue(eventSource.events().isEmpty)
  }

  func testValidRetryTimeoutUpdate() throws {
    
    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"]
          ])
          
          // Send retry time update
          
          res.send(chunk: "retry: 123456789\n\n".data(using: .utf8)!)
          
          // Send real message to complete test
          
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
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }
    
    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }
    
    let eventSource =
      EventSource {
        let request = URLRequest(url: URL(string: "/simple", relativeTo: serverURL)!).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }
    
    let messageX = expectation(description: "Event Received")
    
    eventSource.onMessage { (id, event, data) in
      eventSource.close()
      messageX.fulfill()
    }
    
    eventSource.connect()
    
    waitForExpectations(timeout: 1.0, handler: nil)
    
    XCTAssertEqual(eventSource.retryTime, .milliseconds(123456789))
  }

  func testInvalidRetryTimeoutUpdateIgnored() throws {
    
    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"]
          ])
          
          // Send retry time update along with real message (this is not allowed)

          res.send(chunk: "retry: 123456789\n".data(using: .utf8)!)
          res.send(chunk: "event: test\n".data(using: .utf8)!)
          res.send(chunk: "id: 123\n".data(using: .utf8)!)
          res.send(chunk: "data: {\"some\":\r".data(using: .utf8)!)
          res.send(chunk: "data: \"test data\"}\n\n".data(using: .utf8)!)
          
          // Send real message to complete test
          
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
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }
    
    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }
    
    let eventSource =
      EventSource {
        let request = URLRequest(url: URL(string: "/simple", relativeTo: serverURL)!).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }
    
    let messageX = expectation(description: "Event Received")
    
    eventSource.onMessage { (id, event, data) in
      eventSource.close()
      messageX.fulfill()
    }
    
    eventSource.connect()
    
    waitForExpectations(timeout: 1.0, handler: nil)
    
    XCTAssertEqual(eventSource.retryTime, .milliseconds(500))
  }

}
