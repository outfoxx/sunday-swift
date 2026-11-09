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
@testable import SundayServer
import Synchronization
import XCTest

@MainActor
final class EventSourceCancellationTests: XCTestCase {
  private final class Stop: RequestCancellationError {}

  func testSupersededFactoryCancellationDoesNotCloseReplacement() async throws {
    try await checkSupersededCancellation(inFactory: true)
  }

  func testSupersededRequestCancellationDoesNotCloseReplacement() async throws {
    try await checkSupersededCancellation(inFactory: false)
  }

  private func checkSupersededCancellation(inFactory: Bool) async throws {
    let entered = expectation(description: "old connection suspended")
    let opened = expectation(description: "replacement opened")
    let staleError = expectation(description: "old cancellation ignored")
    staleError.isInverted = true
    let release = NativeTaskResult<Void>()
    let calls = Mutex(0)
    let source = EventSource { _ in
      let call = calls.withLock { $0 += 1; return $0 }
      if call == 1 {
        if inFactory {
          entered.fulfill()
          try await release.value()
          throw CancellationError()
        }
        return URLSession.DataEventStream(request: {
          entered.fulfill()
          try await release.value()
          throw CancellationError()
        })
      }
      return Self.openStream()
    }
    defer { release.complete(.success(())); Task { await source.close() } }
    await source.setOnError { error in if error != nil { staleError.fulfill() } }
    await source.setOnOpen { opened.fulfill() }
    await source.connect()
    await fulfillment(of: [entered], timeout: 3)
    await source.close()
    await source.connect()
    await fulfillment(of: [opened], timeout: 3)
    release.complete(.success(()))
    await fulfillment(of: [staleError], timeout: 0.3)
    let state = await source.readyState
    XCTAssertEqual(state, .open)
    XCTAssertEqual(calls.withLock { $0 }, 2)
    await source.close()
  }

  func testActiveConnectionStillReportsCancellationAndStopErrors() async {
    for error: any Error in [CancellationError(), Stop()] {
      let closed = expectation(description: "active connection stops")
      let source = EventSource { _ in throw error }
      await source.setOnStateError { reported, state in
        XCTAssertNotNil(reported)
        XCTAssertEqual(state, .closed)
        closed.fulfill()
      }
      await source.connect()
      await fulfillment(of: [closed], timeout: 3)
    }
  }

  func testEventTimeoutReconnectsAfterCancellingNativeRead() async throws {
    let calls = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") { GET { _, response in
        let call = calls.withLock { $0 += 1; return $0 }
        response.start(status: .ok, headers: [
          HTTP.StdHeaders.contentType: ["text/event-stream"],
          HTTP.StdHeaders.transferEncoding: ["chunked"],
        ])
        response.send(chunk: call == 1 ? "retry: 10\n\n" : "data: replacement\n\n")
      } }
    }
    let base = try await startTestServer(server)
    let session = URLSession(configuration: .ephemeral)
    let source = EventSource(eventTimeoutInterval: .milliseconds(100),
                             eventTimeoutCheckInterval: .milliseconds(20)) { _ in
      try session.dataEventStream(for: URLRequest(url: base.appendingPathComponent("events")))
    }
    defer { session.invalidateAndCancel(); server.stop(); Task { await source.close() } }
    let received = expectation(description: "replacement sends events")
    await source.setOnMessage { _, _, data in
      XCTAssertEqual(data, "replacement")
      Task { await source.close(); received.fulfill() }
    }
    await source.setOnError { error in
      if let error { XCTAssertEqual(error as? EventSource.Error, .eventTimeout) }
    }
    await source.connect()
    await fulfillment(of: [received], timeout: 5)
    XCTAssertEqual(calls.withLock { $0 }, 2)
  }

  private nonisolated static func openStream() -> URLSession.DataEventStream {
    URLSession.DataEventStream(events: AsyncThrowingStream { continuation in
      let response = HTTPURLResponse(url: URL(string: "https://example.test/events")!, statusCode: 200,
                                     httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
      continuation.yield(.connect(response))
    })
  }
}
