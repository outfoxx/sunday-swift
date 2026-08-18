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
import Synchronization
import XCTest


private final class TestEventWriter: Sendable {

  let response: HTTPResponse

  init(response: HTTPResponse) {
    self.response = response
  }

  func sendJSONEvent(repeatAfter delay: TimeInterval? = nil, finishAfterEvent: Bool = false) {
    response.send(chunk: "event: test\n")
    response.send(chunk: "id: 123\n")
    response.send(chunk: "data: {\"some\":\r")
    response.send(chunk: "data: \"test data\"}\n")
    response.send(chunk: "\n")

    if finishAfterEvent {
      response.finish(trailers: [:])
    }

    if let delay = delay {
      response.server.queue.asyncAfter(deadline: .now() + delay) { self.sendJSONEvent(repeatAfter: delay) }
    }
  }

  func sendRetryThenJSONEvent(_ retry: String, finishAfterEvent: Bool = false) {
    response.send(chunk: "retry: \(retry)\n\n")
    response.server.queue.asyncAfter(deadline: .now() + 0.5) {
      self.sendJSONEvent(finishAfterEvent: finishAfterEvent)
    }
  }

  func sendInvalidRetryAndJSONEvent(repeatAfter delay: TimeInterval) {
    response.send(chunk: "retry: abc\n")
    sendJSONEvent()
    response.server.queue.asyncAfter(deadline: .now() + delay) { self.sendInvalidRetryAndJSONEvent(repeatAfter: delay) }
  }

  func sendInvalidRetryAndJSONEvent(finishAfterEvent: Bool = false) {
    response.send(chunk: "retry: abc\n")
    sendJSONEvent(finishAfterEvent: finishAfterEvent)
  }

}


private enum TestEventStreamError: Error, Sendable {
  case interrupted
}


@MainActor
class EventSourceTests: XCTestCase {

  func testCancelledTaskDoesNotConnect() async {

    let eventSource =
      EventSource { _ in
        URLSession.DataEventStream(events: AsyncThrowingStream { _ in })
      }
    defer { Task { await eventSource.close() } }

    let connectTask = Task {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      await eventSource.connect()
    }

    await connectTask.value

    let readyState = await eventSource.readyState
    XCTAssertEqual(readyState, .closed)
  }

  func testIgnoresDoubleConnect() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.send(chunk: "data: test\n\n")
          res.finish(trailers: [:])
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }
    defer { Task { await eventSource.close() } }

    let messageX = expectation(description: "Event Received")

    await eventSource.setOnMessage { _, _, _ in
      Task {
        await eventSource.close()
        messageX.fulfill()
      }
    }

    await eventSource.connect()
    await eventSource.connect()

    await fulfillment(of: [messageX], timeout: 90)
  }

  func testSimpleData() async throws {

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

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }
    defer { Task { await eventSource.close() } }

    let messageX = expectation(description: "Event Received")

    await eventSource.setOnMessage { event, id, data in
      XCTAssertEqual(id, "123")
      XCTAssertEqual(event, "test")
      XCTAssertEqual(data, "some test data")
      Task {
        await eventSource.close()
        messageX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [messageX], timeout: 90)
  }

  func testJSONData() async throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/json") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])

          TestEventWriter(response: res).sendJSONEvent(finishAfterEvent: true)
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/json", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }
    defer { Task { await eventSource.close() } }

    let messagedX = expectation(description: "Event Received")

    await eventSource.setOnMessage { event, id, data in
      XCTAssertEqual(event, "test")
      XCTAssertEqual(id, "123")
      XCTAssertEqual(data, "{\"some\":\n\"test data\"}")
      Task {
        await eventSource.close()
        messagedX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [messagedX], timeout: 30)
  }

  func testCallbacks() async throws {

    let eventSource: EventSource =
      EventSource { _ in
        Self.dataEventStream(data: "event: test\ndata: event\n\n", finishesAfter: 1.0)
      }
    defer { Task { await eventSource.close() } }

    let openX = expectation(description: "Open Received")
    let messageX = expectation(description: "Message Received")
    let listenerX = expectation(description: "Listener Received")

    await eventSource.setOnOpen { openX.fulfill() }

    await eventSource.setOnMessage { _, _, _ in messageX.fulfill() }

    await eventSource.addEventListener(for: "test") { _, _, _ in
      Task {
        await eventSource.close()
        listenerX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [openX, messageX, listenerX], timeout: 30)
  }

  func testEventListenerRemove() async throws {

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "http://example.com/simple"))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }

    let handlerId = await eventSource.addEventListener(for: "test") { _, _, _ in }
    let listenerTypes = await eventSource.registeredListenerTypes()
    XCTAssertTrue(!listenerTypes.isEmpty)

    await eventSource.removeEventListener(handlerId: handlerId, for: "test")
    let remainingListenerTypes = await eventSource.registeredListenerTypes()
    XCTAssertTrue(remainingListenerTypes.isEmpty)
  }

  func testValidRetryTimeoutUpdate() async throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in

          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])

          let eventWriter = TestEventWriter(response: res)
          res.server.queue.asyncAfter(deadline: .now() + 0.5) {
            eventWriter.sendRetryThenJSONEvent("123456789", finishAfterEvent: true)
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }

    let messageX = expectation(description: "Event Received")

    await eventSource.setOnMessage { _, _, _ in
      Task {
        await eventSource.close()
        messageX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [messageX], timeout: 30)

    let retryTime = await eventSource.retryTime
    XCTAssertEqual(retryTime, .milliseconds(123_456_789))
  }

  func testInvalidRetryTimeoutUpdateIgnored() async throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in

          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])

          let eventWriter = TestEventWriter(response: res)
          eventWriter.sendInvalidRetryAndJSONEvent(finishAfterEvent: true)
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
      }

    let messageX = expectation(description: "Event Received")
    messageX.assertForOverFulfill = false

    await eventSource.setOnMessage { _, _, _ in
      Task {
        await eventSource.close()
        messageX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [messageX], timeout: 30)

    let retryTime = await eventSource.retryTime
    XCTAssertEqual(retryTime, .milliseconds(500))
  }

  func testInvalidNumericReconnectControlsAreIgnored() async throws {

    let eventSource =
      EventSource { _ in
        Self.dataEventStream(
          data: "retry: -1\nretry-max: 1.5\nkeepalive: +100\ndata: configured\n\n",
          finishes: false
        )
      }
    defer { Task { await eventSource.close() } }

    let messageX = expectation(description: "Event Received")

    await eventSource.setOnMessage { _, _, _ in
      messageX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [messageX], timeout: 30)

    let retryTime = await eventSource.retryTime
    let retryTimeMaximum = await eventSource.retryTimeMaximum
    let serverEventTimeoutInterval = await eventSource.serverEventTimeoutInterval
    XCTAssertEqual(retryTime, .milliseconds(500))
    XCTAssertNil(retryTimeMaximum)
    XCTAssertNil(serverEventTimeoutInterval)
  }

  func testServerReconnectControlsUpdate() async throws {

    let eventSource =
      EventSource { _ in
        Self.dataEventStream(
          data: "retry-max: 750\nkeepalive: 100\ndata: configured\n\n",
          finishes: false
        )
      }
    defer { Task { await eventSource.close() } }

    let messageX = expectation(description: "Event Received")

    await eventSource.setOnMessage { _, _, _ in
      messageX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [messageX], timeout: 30)

    let retryTimeMaximum = await eventSource.retryTimeMaximum
    let serverEventTimeoutInterval = await eventSource.serverEventTimeoutInterval
    XCTAssertEqual(retryTimeMaximum, .milliseconds(750))
    XCTAssertEqual(serverEventTimeoutInterval, .seconds(1))
  }

  func testZeroRetryMaximumIsIgnored() async throws {

    let eventSource =
      EventSource { _ in
        Self.dataEventStream(
          data: "retry-max: 750\ndata: configured\n\nretry-max: 0\ndata: unchanged\n\n",
          finishes: false
        )
      }
    defer { Task { await eventSource.close() } }

    let messageX = expectation(description: "Events Received")
    messageX.expectedFulfillmentCount = 2

    await eventSource.setOnMessage { _, _, _ in
      messageX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [messageX], timeout: 30)

    let retryTimeMaximum = await eventSource.retryTimeMaximum
    XCTAssertEqual(retryTimeMaximum, .milliseconds(750))
  }

  func testReconnectsWithLastEventId() async throws {

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
              reconnectX.fulfill()

              res.send(status: .serviceUnavailable)
            }
          }
        }
      }
    }
    guard let serverURL = server.startLocal(timeout: 30.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
    }
    defer { Task { await eventSource.close() } }

    await eventSource.connect()

    await fulfillment(of: [reconnectX], timeout: 90)
    await eventSource.close()
  }

  func testReconnectsWithLastEventIdIgnoringInvalidIDs() async throws {

    let reconnectX = expectation(description: "reconnection")
    let connectionCount = Mutex(0)

    let eventSource =
      EventSource { headers in
        let connection = connectionCount.withLock { count in
          defer { count += 1 }
          return count
        }

        if connection == 0 {
          return Self.dataEventStream(
            data: "id: 123\nevent: test\ndata: Hello!\n\nid: a\0c\nevent: test\ndata: Hello!\n\n"
          )
        }

        XCTAssertEqual(connection, 1)
        XCTAssertEqual(headers[HTTP.StdHeaders.lastEventId], ["123"])
        reconnectX.fulfill()

        return nil
      }
    defer { Task { await eventSource.close() } }

    await eventSource.connect()

    await fulfillment(of: [reconnectX], timeout: 30)
    await eventSource.close()
  }

  func testReconnectClearsPartialEventData() async throws {

    let messageX = expectation(description: "message")
    let connectionCount = Mutex(0)

    let eventSource =
      EventSource { _ in
        let connection = connectionCount.withLock { count in
          defer { count += 1 }
          return count
        }

        if connection == 0 {
          return Self.dataEventStream(data: "data: stale")
        }

        return Self.dataEventStream(data: "event: test\ndata: fresh\n\n", finishes: false)
      }
    defer { Task { await eventSource.close() } }

    await eventSource.setOnMessage { _, _, data in
      XCTAssertEqual(data, "fresh")
      Task {
        await eventSource.close()
        messageX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [messageX], timeout: 30)
    XCTAssertEqual(connectionCount.withLock { $0 }, 2)
  }

  func testEventTimeoutCheckWithExpiration() async throws {

    let eventSource: EventSource =
      EventSource(eventTimeoutInterval: .milliseconds(500), eventTimeoutCheckInterval: .milliseconds(100)) { _ in
        Self.dataEventStream(data: "id: 123\nevent: test\ndata: Hello!\n\n", finishesAfter: 5.0)
      }
    defer { Task { await eventSource.close() } }

    let errorX = expectation(description: "error received")
    let didReceiveTimeout = Mutex(false)

    await eventSource.setOnError { error in
      if let error = error as? EventSource.Error, EventSource.Error.eventTimeout == error {
        guard didReceiveTimeout.withLock({ didReceiveTimeout in
          guard !didReceiveTimeout else {
            return false
          }

          didReceiveTimeout = true
          return true
        }) else {
          return
        }

        Task {
          await eventSource.close()
          errorX.fulfill()
        }
      }
    }

    await eventSource.connect()

    await fulfillment(of: [errorX], timeout: 30)
  }

  func testEventTimeoutCheckWithoutExpiration() async throws {

    let eventSource =
      EventSource(eventTimeoutInterval: .milliseconds(500), eventTimeoutCheckInterval: .milliseconds(100)) { _ in
        Self.dataEventStream(
          data: "id: 123\nevent: test\ndata: Hello!\n\n",
          throwsAfter: .milliseconds(300)
        )
      }
    defer { Task { await eventSource.close() } }

    let errorX = expectation(description: "error received")
    let didReceiveError = Mutex(false)

    await eventSource.setOnError { error in
      guard didReceiveError.withLock({ didReceiveError in
        guard !didReceiveError else {
          return false
        }

        didReceiveError = true
        return true
      }) else {
        return
      }

      if let error = error as? EventSource.Error, EventSource.Error.eventTimeout == error {
        XCTFail("Expected transport error before event timeout")
      }

      Task {
        await eventSource.close()
        errorX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [errorX], timeout: 30)
  }

  func testKeepaliveEnablesEventTimeoutWhenDefaultIsDisabled() async throws {

    XCTAssertNil(EventSource.eventTimeoutIntervalDefault)

    let eventSource =
      EventSource(eventTimeoutCheckInterval: .milliseconds(20)) { _ in
        Self.dataEventStream(data: "keepalive: 1\n\n", finishes: false)
      }
    defer { Task { await eventSource.close() } }

    let errorX = expectation(description: "Event Timeout")

    await eventSource.setOnError { error in
      guard let error = error as? EventSource.Error, error == .eventTimeout else {
        return
      }

      Task {
        await eventSource.close()
        errorX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [errorX], timeout: 3)
  }

  func testExplicitEventTimeoutOverridesKeepalive() async throws {

    let eventSource =
      EventSource(eventTimeoutInterval: .milliseconds(100), eventTimeoutCheckInterval: .milliseconds(20)) { _ in
        Self.dataEventStream(data: "keepalive: 60000\n\n", finishes: false)
      }
    defer { Task { await eventSource.close() } }

    let errorX = expectation(description: "Event Timeout")

    await eventSource.setOnError { error in
      guard let error = error as? EventSource.Error, error == .eventTimeout else {
        return
      }

      Task {
        await eventSource.close()
        errorX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [errorX], timeout: 3)
  }

  func testCloseWhenTransportReturnsNil() async throws {

    let eventSource =
    EventSource { _ in
      nil as URLSession.DataEventStream?
    }

    let closeErrorX = expectation(description: "EventSource Close Error")

    await eventSource.setOnStateError { error, readyState in
      guard let error = error as? EventSource.Error, case .requestStreamEmpty = error else {
        return
      }
      XCTAssertEqual(readyState, .closed)
      closeErrorX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [closeErrorX], timeout: 30)
  }

  func testCloseWhenTransportIsCancelled() async throws {

    let eventSource =
    EventSource { _ in
      URLSession.DataEventStream(events: AsyncThrowingStream { continuation in
        continuation.yield(.connect(Self.eventStreamResponse()))
        continuation.finish(throwing: URLError(.cancelled))
      })
    }

    let closeErrorX = expectation(description: "EventSource Close Error")

    await eventSource.setOnStateError { error, readyState in
      guard isCancellationError(error) else {
        XCTFail("Expected cancellation error, got \(String(describing: error))")
        closeErrorX.fulfill()
        return
      }

      XCTAssertEqual(readyState, .closed)
      closeErrorX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [closeErrorX], timeout: 30)
  }

  func testCloseCancelsQueuedReconnectAfterCallbacks() async throws {

    let errorX = expectation(description: "EventSource Error")
    let reconnectX = expectation(description: "EventSource Reconnect")
    reconnectX.isInverted = true
    let connectionCount = Mutex(0)
    let handledError = Mutex(false)

    let eventSource =
      EventSource(queue: DispatchQueue(label: "io.outfoxx.sunday.EventSourceTests.reconnect")) { _ in
        let connection = connectionCount.withLock { count in
          defer { count += 1 }
          return count
        }

        guard connection == 0 else {
          reconnectX.fulfill()
          return nil
        }

        return Self.dataEventStream(
          data: "event: test\ndata: event\n\n",
          finishes: false,
          throwsAfter: .milliseconds(10)
        )
      }
    defer { Task { await eventSource.close() } }

    await eventSource.setOnError { error in
      guard error != nil else {
        return
      }

      let shouldHandle = handledError.withLock { handledError in
        guard !handledError else {
          return false
        }

        handledError = true
        return true
      }

      guard shouldHandle else {
        return
      }

      Task {
        await eventSource.close()
      }
      Thread.sleep(forTimeInterval: 0.05)
      errorX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [errorX], timeout: 30)
    await fulfillment(of: [reconnectX], timeout: 0.5)
    XCTAssertEqual(connectionCount.withLock { $0 }, 1)
    await eventSource.close()
  }

  func testDuplicateConnectWhileOpenReportsInvalidState() async throws {

    let invalidStateX = expectation(description: "invalid state")
    let secondOpenX = expectation(description: "second open")
    secondOpenX.isInverted = true
    let openCount = Mutex(0)

    let eventSource =
      EventSource { _ in
        URLSession.DataEventStream(events: AsyncThrowingStream { continuation in
          continuation.yield(.connect(Self.eventStreamResponse()))
          continuation.yield(.connect(Self.eventStreamResponse()))
          continuation.finish()
        })
      }
    defer { Task { await eventSource.close() } }

    await eventSource.setOnOpen {
      let count = openCount.withLock { count -> Int in
        count += 1
        return count
      }
      if count > 1 {
        secondOpenX.fulfill()
      }
    }

    await eventSource.setOnError { error in
      guard let error = error as? EventSource.Error, case .invalidState = error else {
        return
      }
      Task {
        await eventSource.close()
        invalidStateX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [invalidStateX], timeout: 30)
    await fulfillment(of: [secondOpenX], timeout: 0.5)
    XCTAssertEqual(openCount.withLock { $0 }, 1)
  }

  func testConcurrentConnectStartsOneTransportStream() async throws {

    let connectionCount = Mutex(0)
    let connectionX = expectation(description: "EventSource Connected")
    let duplicateConnectionX = expectation(description: "EventSource Duplicate Connection")
    duplicateConnectionX.isInverted = true

    let eventSource =
      EventSource { _ in
        let count = connectionCount.withLock { count in
          count += 1
          return count
        }
        if count == 1 {
          connectionX.fulfill()
        }
        else {
          duplicateConnectionX.fulfill()
        }
        return Self.dataEventStream(data: "event: test\ndata: event\n\n", finishesAfter: 1.2)
      }
    defer { Task { await eventSource.close() } }

    await withTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 50 {
        group.addTask {
          await eventSource.connect()
        }
      }
    }

    await fulfillment(of: [connectionX, duplicateConnectionX], timeout: 1.0)
    await eventSource.close()
    XCTAssertEqual(connectionCount.withLock { $0 }, 1)
  }

  func testCallbacksCanReadReadyStateOnSerialQueue() async throws {

    let eventSource =
      EventSource(queue: DispatchQueue(label: "io.outfoxx.sunday.EventSourceTests.callbacks")) { _ in
        Self.dataEventStream(data: "event: test\ndata: event\n\n", finishesAfter: 0.2)
      }
    defer { Task { await eventSource.close() } }

    let openX = expectation(description: "Open Received")

    await eventSource.setOnOpen {
      Task {
        let readyState = await eventSource.readyState
        XCTAssertEqual(readyState, .open)
        openX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [openX], timeout: 30)
    await eventSource.close()
  }

  func testSuccessfulConnectionResetsRetryAttempt() async throws {

    let connectionCount = Mutex(0)
    let eventSource =
      EventSource { _ in
        let connection = connectionCount.withLock { count in
          defer { count += 1 }
          return count
        }

        if connection == 0 {
          throw TestEventStreamError.interrupted
        }

        return Self.dataEventStream(data: "", finishes: false)
      }
    defer { Task { await eventSource.close() } }

    let openX = expectation(description: "EventSource Opened")

    await eventSource.setOnOpen {
      Task {
        let retryAttempt = await eventSource.retryAttempt
        XCTAssertEqual(retryAttempt, 0)
        await eventSource.close()
        openX.fulfill()
      }
    }

    await eventSource.connect()

    await fulfillment(of: [openX], timeout: 3)
    XCTAssertEqual(connectionCount.withLock { $0 }, 2)
  }

  func testCheckRetryDelays() {

    let delays = (0 ... 6).map {
      EventSource.calculateRetryDelay(
        retryAttempt: $0,
        retryTime: .milliseconds(500),
        retryTimeMaximum: nil,
        jitterFactor: 1
      )
    }

    XCTAssertEqual(delays, [
      .milliseconds(500),
      .seconds(1),
      .seconds(2),
      .seconds(4),
      .seconds(8),
      .seconds(15),
      .seconds(15),
    ])

    let serverCappedDelay = EventSource.calculateRetryDelay(
      retryAttempt: 4,
      retryTime: .milliseconds(500),
      retryTimeMaximum: .seconds(3),
      jitterFactor: 1
    )
    XCTAssertEqual(serverCappedDelay, .seconds(3))

    let jitteredDelay = EventSource.calculateRetryDelay(
      retryAttempt: 1,
      retryTime: .milliseconds(500),
      retryTimeMaximum: nil,
      jitterFactor: 0.9
    )
    XCTAssertEqual(jitteredDelay, .milliseconds(900))
  }

  func testNoContentResponseStopsWithoutReconnecting() async throws {

    let connectionCount = Mutex(0)
    let reconnectX = expectation(description: "EventSource Reconnected")
    reconnectX.isInverted = true
    let eventSource =
      EventSource { _ in
        let count = connectionCount.withLock { count in
          count += 1
          return count
        }
        if count > 1 {
          reconnectX.fulfill()
        }
        return Self.dataEventStream(statusCode: 204, data: "")
      }
    defer { Task { await eventSource.close() } }

    let closeX = expectation(description: "EventSource Closed")

    await eventSource.setOnStateError { error, readyState in
      guard readyState == .closed else {
        return
      }

      guard let error = error as? SundayError,
            case .responseValidationFailed(reason: .unacceptableStatusCode) = error
      else {
        XCTFail("Expected unacceptable status error, got \(String(describing: error))")
        closeX.fulfill()
        return
      }

      closeX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [closeX], timeout: 3)
    await fulfillment(of: [reconnectX], timeout: 0.75)
    XCTAssertEqual(connectionCount.withLock { $0 }, 1)
  }

  func testHTTPValidationFailureStopsWithoutReconnecting() async throws {

    let response = Self.eventStreamResponse(statusCode: 404)
    let connectionCount = Mutex(0)
    let reconnectX = expectation(description: "EventSource Reconnected")
    reconnectX.isInverted = true
    let eventSource =
      EventSource { _ -> URLSession.DataEventStream? in
        let count = connectionCount.withLock { count in
          count += 1
          return count
        }
        if count > 1 {
          reconnectX.fulfill()
        }
        throw SundayError.responseValidationFailed(
          reason: .unacceptableStatusCode(response: response, data: nil)
        )
      }
    defer { Task { await eventSource.close() } }

    let closeX = expectation(description: "EventSource Closed")

    await eventSource.setOnStateError { error, readyState in
      guard readyState == .closed else {
        return
      }

      guard let error = error as? SundayError,
            case .responseValidationFailed(reason: .unacceptableStatusCode) = error
      else {
        XCTFail("Expected unacceptable status error, got \(String(describing: error))")
        closeX.fulfill()
        return
      }

      closeX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [closeX], timeout: 3)
    await fulfillment(of: [reconnectX], timeout: 0.75)
    XCTAssertEqual(connectionCount.withLock { $0 }, 1)
  }

  func testPingsResetLastEventReceivedTime() async throws {

    let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/simple") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.server.queue.asyncAfter(deadline: .now().advanced(by: .seconds(1))) {
            res.send(chunk: ": ping\n\n")
            res.server.queue.asyncAfter(deadline: .now() + 0.1) {
              res.finish(trailers: [:])
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

    let session = URLSession(configuration: .default)
    defer { session.close(cancelOutstandingTasks: true) }

    let url = try XCTUnwrap(URL(string: "/simple", relativeTo: serverURL))
    let eventSource =
      EventSource {
        let request = URLRequest(url: url).adding(httpHeaders: $0)
        return try session.dataEventStream(for: request)
    }
    defer { Task { await eventSource.close() } }

    let openX = expectation(description: "Open Received")
    let didOpen = Mutex(false)
    await eventSource.setOnOpen {
      let shouldFulfill = didOpen.withLock { didOpen in
        guard !didOpen else {
          return false
        }

        didOpen = true
        return true
      }
      if shouldFulfill {
        openX.fulfill()
      }
    }

    let initialLastEventReceivedTime = await eventSource.lastEventReceivedTime
    XCTAssertEqual(initialLastEventReceivedTime, .distantFuture)

    await eventSource.connect()

    await fulfillment(of: [openX], timeout: 30)

    let openedAt = await eventSource.lastEventReceivedTime
    XCTAssertNotEqual(openedAt, .distantFuture)

    let timeout = ContinuousClock.now + .seconds(30)
    while await eventSource.lastEventReceivedTime == openedAt {
      if ContinuousClock.now >= timeout {
        XCTFail("Timed out waiting for ping to reset lastEventReceivedTime")
        return
      }

      try await Task.sleep(for: .milliseconds(50))
    }

    let lastEventReceivedTime = await eventSource.lastEventReceivedTime
    XCTAssertLessThan(DispatchTime.now().distance(to: lastEventReceivedTime).totalSeconds, 0.5)
    await eventSource.close()
  }

  private nonisolated static func dataEventStream(
    statusCode: Int = 200,
    data: String,
    finishes: Bool = true,
    finishesAfter: TimeInterval? = nil,
    throwsAfter: DispatchTimeInterval? = nil
  ) -> URLSession.DataEventStream {
    return URLSession.DataEventStream(events: AsyncThrowingStream { continuation in
      continuation.yield(.connect(Self.eventStreamResponse(statusCode: statusCode)))
      continuation.yield(.data(Data(data.utf8)))
      let finishDelay = finishesAfter.map { DispatchTimeInterval.milliseconds(Int($0 * 1000)) }
      if let streamCompletionDelay = finishDelay ?? throwsAfter {
        let streamTask = Task {
          try? await Task.sleep(for: .milliseconds(streamCompletionDelay.totalMilliseconds))
          guard !Task.isCancelled else {
            return
          }
          if throwsAfter != nil {
            continuation.finish(throwing: TestEventStreamError.interrupted)
          }
          else {
            continuation.finish()
          }
        }
        continuation.onTermination = { _ in
          streamTask.cancel()
        }
      }
      else if finishes {
        continuation.finish()
      }
    })
  }

  private nonisolated static func eventStreamResponse(statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
      url: URL(string: "http://example.com/events")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: [
        HTTP.StdHeaders.contentType: MediaType.eventStream.value,
      ]
    )!
  }

}

private func isCancellationError(_ error: (any Error)?) -> Bool {
  switch error {
  case let error as URLError where error.code == .cancelled:
    return true
  case is CancellationError:
    return true
  default:
    return false
  }
}
