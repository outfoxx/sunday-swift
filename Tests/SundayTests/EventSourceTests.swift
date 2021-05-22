//
//  EventSourceTests.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Sunday
import SundayServer
import XCTest


class EventSourceTests: XCTestCase {

  func testIgnoresDoubleConnect() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          res.send(status: .ok, text: "data: test\n\n")
        }
      }
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    let messageX = expectation(description: "Event Received")

    eventSource.onMessage { _, _, _ in
      eventSource.close()
      messageX.fulfill()
    }

    eventSource.connect()
    eventSource.connect()

    waitForExpectations(timeout: 5.0, handler: nil)
  }

  func testSimpleData() throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.send(chunk: "event: test\n".data(using: .utf8) ?? Data())
          res.send(chunk: "id: 123\n".data(using: .utf8) ?? Data())
          res.send(chunk: "data: some test data\n\n".data(using: .utf8) ?? Data())
          res.finish(trailers: [:])
        }
      }
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    let messageX = expectation(description: "Event Received")

    eventSource.onMessage { event, id, data in
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
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.send(chunk: "event: test\n".data(using: .utf8) ?? Data())
          res.send(chunk: "id: 123\n".data(using: .utf8) ?? Data())
          res.send(chunk: "data: {\"some\":\r".data(using: .utf8) ?? Data())
          res.send(chunk: "data: \"test data\"}\n\n".data(using: .utf8) ?? Data())
          res.finish(trailers: [:])
        }
      }
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/json", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    let messagedX = expectation(description: "Event Received")

    eventSource.onMessage { event, id, data in
      XCTAssertEqual(event, "test")
      XCTAssertEqual(id, "123")
      XCTAssertEqual(data, "{\"some\":\n\"test data\"}")
      messagedX.fulfill()
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
                HTTP.StdHeaders.transferEncoding: ["chunked"],
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
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    let openX = expectation(description: "Open Received")
    let messageX = expectation(description: "Message Received")
    let listenerX = expectation(description: "Listener Received")
    let errorX = expectation(description: "Error Received")
    errorX.assertForOverFulfill = false

    eventSource.onOpen { openX.fulfill() }

    eventSource.onMessage { _, _, _ in messageX.fulfill() }

    eventSource.addEventListener("test") { _, _, _ in
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

    let url = try XCTUnwrap(URL(string: "http://example.com/simple"))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
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
            HTTP.StdHeaders.transferEncoding: ["chunked"],
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
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    let messageX = expectation(description: "Event Received")

    eventSource.onMessage { _, _, _ in
      eventSource.close()
      messageX.fulfill()
    }

    eventSource.connect()

    waitForExpectations(timeout: 1.0, handler: nil)

    XCTAssertEqual(eventSource.retryTime, .milliseconds(123_456_789))
  }

  func testInvalidRetryTimeoutUpdateIgnored() throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in

          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])

          res.send(chunk: "retry: abc\n".data(using: .utf8)!)
          res.send(chunk: "event: test\n".data(using: .utf8)!)
          res.send(chunk: "id: 123\n".data(using: .utf8)!)
          res.send(chunk: "data: {\"some\":\r".data(using: .utf8)!)
          res.send(chunk: "data: \"test data\"}\n\n".data(using: .utf8)!)

          res.finish(trailers: [:])
        }
      }
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    let messageX = expectation(description: "Event Received")

    eventSource.onMessage { _, _, _ in
      eventSource.close()
      messageX.fulfill()
    }

    eventSource.connect()

    waitForExpectations(timeout: 1.0, handler: nil)

    XCTAssertEqual(eventSource.retryTime, .milliseconds(500))
  }

  func testReconnectsWithLastEventId() throws {

    let reconnectX = expectation(description: "reconnection")

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        TrackInvocations(name: "invocations") {
          GET { req, res in

            let invocations = res.properties["invocations"] as! Int
            if invocations == 0 {
              res.start(status: .ok, headers: [
                HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
                HTTP.StdHeaders.transferEncoding: ["chunked"],
              ])

              res.send(chunk: "id: 123\nevent: test\ndata: Hello!\n\n".data(using: .utf8)!)
              res.finish(trailers: [:])
            }
            else {
              XCTAssertEqual(req.header(for: "last-event-id"), "123")

              res.send(status: .serviceUnavailable)

              reconnectX.fulfill()
            }
          }
        }
      }
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    eventSource.onError { _ in
      eventSource.close()
    }

    eventSource.connect()

    waitForExpectations(timeout: 2.0, handler: nil)
  }

  func testReconnectsWithLastEventIdIgnoringInvalidIDs() throws {

    let reconnectX = expectation(description: "reconnection")

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        TrackInvocations(name: "invocations") {
          GET { req, res in

            let invocations = res.properties["invocations"] as! Int
            if invocations == 0 {
              res.start(status: .ok, headers: [
                HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
                HTTP.StdHeaders.transferEncoding: ["chunked"],
              ])

              res.send(chunk: "id: 123\nevent: test\ndata: Hello!\n\n".data(using: .utf8)!)

              // Send event ID with NULL character
              res.send(chunk: "id: a\0c\nevent: test\ndata: Hello!\n\n".data(using: .utf8)!)

              res.finish(trailers: [:])
            }
            else {
              XCTAssertEqual(req.header(for: "last-event-id"), "123")

              res.send(status: .serviceUnavailable)

              reconnectX.fulfill()
            }
          }
        }
      }
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    eventSource.onError { _ in
      eventSource.close()
    }

    eventSource.connect()

    waitForExpectations(timeout: 2.0, handler: nil)
  }

  func testEventTimeoutCheckWithExpiration() throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        TrackInvocations(name: "invocations") {
          GET { _, res in

            res.start(status: .ok, headers: [
              HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
              HTTP.StdHeaders.transferEncoding: ["chunked"],
            ])

            res.send(chunk: "id: 123\nevent: test\ndata: Hello!\n\n".data(using: .utf8)!)

          }
        }
      }
      CatchAll { route, req, _ in
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

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource(eventTimeoutInterval: .milliseconds(500), eventTimeoutCheckInterval: .milliseconds(100)) {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    let errorX = expectation(description: "error received")

    eventSource.onError { error in
      if let error = error as? EventSource.Error, EventSource.Error.eventTimeout == error {
        eventSource.close()
        errorX.fulfill()
      }
    }

    eventSource.connect()

    waitForExpectations(timeout: 3.0, handler: nil)
  }

  func testEventTimeoutCheckWithoutExpiration() throws {

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        TrackInvocations(name: "invocations") {
          GET { req, res in

            res.start(status: .ok, headers: [
              HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
              HTTP.StdHeaders.transferEncoding: ["chunked"],
            ])

            res.send(chunk: "id: 123\nevent: test\ndata: Hello!\n\n".data(using: .utf8)!)

            req.server.queue.asyncAfter(deadline: .now() + .milliseconds(300)) {
              session.close(cancelOutstandingTasks: true)
            }
          }
        }
      }
      CatchAll { route, req, _ in
        print(route)
        print(req)
      }
    }
    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource(eventTimeoutInterval: .milliseconds(500), eventTimeoutCheckInterval: .milliseconds(100)) {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return session.dataTaskStreamPublisher(for: request)
          .eraseToAnyPublisher()
      }

    let errorX = expectation(description: "error received")

    eventSource.onError { _ in
      eventSource.close()
      errorX.fulfill()
    }

    eventSource.connect()

    waitForExpectations(timeout: 3.0, handler: nil)
  }

}
