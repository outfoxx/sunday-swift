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

import Foundation
@testable import Sunday
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
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    let messageX = expectation(description: "Event Received")

    eventSource.onMessage = { _, _, _ in
      eventSource.close()
      messageX.fulfill()
    }

    eventSource.connect()
    eventSource.connect()

    waitForExpectations()
  }

  func testSimpleData() throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.send(chunk: "event: test\n")
          res.send(chunk: "id: 123\n")
          res.send(chunk: "data: some test data\n\n")
          res.finish(trailers: [:])
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    let messageX = expectation(description: "Event Received")

    eventSource.onMessage = { event, id, data in
      eventSource.close()
      XCTAssertEqual(id, "123")
      XCTAssertEqual(event, "test")
      XCTAssertEqual(data, "some test data")
      messageX.fulfill()
    }

    eventSource.connect()

    waitForExpectations()
  }

  func testJSONData() throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/json") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          func sendEvent() {
            res.send(chunk: "event: test\n")
            res.send(chunk: "id: 123\n")
            res.send(chunk: "data: {\"some\":\r")
            res.send(chunk: "data: \"test data\"}\n")
            res.send(chunk: "\n")
            res.server.queue.asyncAfter(deadline: .now() + 1.0) { sendEvent() }
          }
          res.server.queue.asyncAfter(deadline: .now() + 0.5) { sendEvent() }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    let messagedX = expectation(description: "Event Received")

    eventSource.onMessage = { event, id, data in
      XCTAssertEqual(event, "test")
      XCTAssertEqual(id, "123")
      XCTAssertEqual(data, "{\"some\":\n\"test data\"}")
      messagedX.fulfill()
    }

    eventSource.connect()

    waitForExpectations()
  }

  func testCallbacks() throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        TrackInvocations(name: "invocations") {
          GET { _, res in

            // Send event for first request, fail after  that

            let invocations = res.properties["invocations"] as! Int
            if invocations == 0 {

              let headers = [HTTP.StdHeaders.contentType: [MediaType.eventStream.value]]

              res.send(status: .ok, headers: headers, body: Data("event: test\ndata: event\n\n".utf8))
            }
            else {

              res.send(status: .badRequest, text: "fix it")
            }

          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        if session.isClosed {
          throw URLError(.cancelled)
        }
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }

    let openX = expectation(description: "Open Received")
    let messageX = expectation(description: "Message Received")
    let listenerX = expectation(description: "Listener Received")
    let errorX = expectation(description: "Error Received")

    eventSource.onOpen = { openX.fulfill() }

    eventSource.onMessage = { _, _, _ in messageX.fulfill() }

    eventSource.addEventListener(for: "test") { _, _, _ in
      listenerX.fulfill()
    }

    eventSource.onError = { _ in
      eventSource.close()
      errorX.fulfill()
    }

    eventSource.connect()

    waitForExpectations()
  }

  func testEventListenerRemove() throws {

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "http://example.com/simple"))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }

    let handlerId = eventSource.addEventListener(for: "test") { _, _, _ in }
    XCTAssertTrue(!eventSource.registeredListenerTypes().isEmpty)

    eventSource.removeEventListener(handlerId: handlerId, for: "test")
    XCTAssertTrue(eventSource.registeredListenerTypes().isEmpty)
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
          func sendRetryTimeUpdate() {
            res.send(chunk: "retry: 123456789\n\n")
            res.server.queue.asyncAfter(deadline: .now() + 0.5) { sendEvent() }
          }

          // Send real message to complete test
          func sendEvent() {
            res.send(chunk: "event: test\n")
            res.send(chunk: "id: 123\n")
            res.send(chunk: "data: {\"some\":\r")
            res.send(chunk: "data: \"test data\"}\n\n")
          }

          res.server.queue.asyncAfter(deadline: .now() + 0.5) { sendRetryTimeUpdate() }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    let messageX = expectation(description: "Event Received")

    eventSource.onMessage = { _, _, _ in
      eventSource.close()
      messageX.fulfill()
    }

    eventSource.connect()

    waitForExpectations()

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

          func sendEvent() {
            res.send(chunk: "retry: abc\n")
            res.send(chunk: "event: test\n")
            res.send(chunk: "id: 123\n")
            res.send(chunk: "data: {\"some\":\r")
            res.send(chunk: "data: \"test data\"}\n\n")

            res.server.queue.asyncAfter(deadline: .now() + 0.5) { sendEvent() }
          }

          res.server.queue.asyncAfter(deadline: .now() + 0.5) { sendEvent() }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    let messageX = expectation(description: "Event Received")
    messageX.assertForOverFulfill = false

    eventSource.onMessage = { _, _, _ in
      eventSource.close()
      messageX.fulfill()
    }

    eventSource.connect()

    waitForExpectations()

    XCTAssertEqual(eventSource.retryTime, .milliseconds(100))
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

              res.server.queue.asyncAfter(deadline: .now() + 0.5) {

                res.send(chunk: "id: 123\ndata: tester\n\n")

                res.server.queue.asyncAfter(deadline: .now() + 0.5) {
                  res.finish(trailers: [:])
                }
              }
            }
            else {
              XCTAssertEqual(req.header(for: "last-event-id"), "123")

              res.send(status: .serviceUnavailable)

              reconnectX.fulfill()
            }
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    eventSource.onError = { _ in
      eventSource.close()
    }

    eventSource.connect()

    waitForExpectations()
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

              res.server.queue.asyncAfter(deadline: .now() + 0.5) {
                res.send(chunk: "id: 123\nevent: test\ndata: Hello!\n\n")

                res.server.queue.asyncAfter(deadline: .now() + 0.5) {
                  // Send event ID with NULL character
                  res.send(chunk: "id: a\0c\nevent: test\ndata: Hello!\n\n")

                  res.finish(trailers: [:])
                }
              }

            }
            else {
              XCTAssertEqual(req.header(for: "last-event-id"), "123")

              res.send(status: .serviceUnavailable)

              reconnectX.fulfill()
            }
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    eventSource.onError = { _ in
      eventSource.close()
    }

    eventSource.connect()

    waitForExpectations()
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

            res.send(chunk: "id: 123\nevent: test\ndata: Hello!\n\n")

          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    let errorX = expectation(description: "error received")

    eventSource.onError = { error in
      if let error = error as? EventSource.Error, EventSource.Error.eventTimeout == error {
        eventSource.close()
        errorX.fulfill()
      }
    }

    eventSource.connect()

    waitForExpectations()
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

            res.send(chunk: "id: 123\nevent: test\ndata: Hello!\n\n")

            req.server.queue.asyncAfter(deadline: .now() + .milliseconds(300)) {
              session.close(cancelOutstandingTasks: true)
            }
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource(eventTimeoutInterval: .milliseconds(500), eventTimeoutCheckInterval: .milliseconds(100)) {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }

    let errorX = expectation(description: "error received")

    eventSource.onError = { _ in
      eventSource.close()
      errorX.fulfill()
    }

    eventSource.connect()

    waitForExpectations()
  }

  func testCloseWhenRequestFactoryReturnsNil() throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.send(chunk: "event: test\n")
          res.send(chunk: "id: 123\n")
          res.send(chunk: "data: some test data\n\n")
          res.finish(trailers: [:])
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = NetworkSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    var requestsReturned = 0
    let eventSource =
    EventSource {
      if requestsReturned > 1 {
        return nil
      }
      defer { requestsReturned += 1 }
      let request = URLRequest(url: url).adding(httpHeaders: $0)
      return try session.dataEventStream(for: request)
    }

    let closeErrorX = expectation(description: "EventSource Close Error")

    eventSource.onError = { error in
      guard let error = error as? EventSource.Error, case .requestStreamEmpty = error else {
        return
      }
      closeErrorX.fulfill()
    }

    eventSource.connect()

    waitForExpectations()
  }

  func testCheckRetryDelays() {

    var delays: [DispatchTimeInterval] = []

    for attempt in 0 ..< 30 {
      delays.append(EventSource.calculateRetryDelay(retryAttempt: attempt,
                                                    retryTime: EventSource.retryTimeDefault,
                                                    lastConnectTime: .milliseconds(0)))
    }

    XCTAssertEqual(delays[0], .milliseconds(0))
    XCTAssertEqual(delays[1], .milliseconds(100))
    XCTAssertGreaterThan(delays[29].totalSeconds, 60)
  }

  func testPingsResetLastEventReceivedTime() throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.server.queue.asyncAfter(deadline: .now().advanced(by: .seconds(1))) {
            res.send(chunk: ": ping\n\n")
            res.finish(trailers: [:])
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
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
        return try session.dataEventStream(for: request)
      }

    eventSource.connect()

    Thread.sleep(forTimeInterval: 0.5)

    XCTAssertEqual(eventSource.lastEventReceivedTime, .distantFuture)

    Thread.sleep(forTimeInterval: 1.5)

    XCTAssertLessThan(DispatchTime.now().distance(to: eventSource.lastEventReceivedTime).totalSeconds, 0.5)
  }

}
