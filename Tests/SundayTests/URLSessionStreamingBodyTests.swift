/*
 * Copyright 2026 Outfox, Inc.
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

import PotentCodables
import Synchronization
import XCTest

@testable import Sunday
@testable import SundayServer


class URLSessionStreamingBodyTests: XCTestCase {

  func testAttachesStreamingFileBody() async throws {

    let body = Data("archive-data".utf8)
    let bodyURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("tar")
    try body.write(to: bodyURL)
    defer { try? FileManager.default.removeItem(at: bodyURL) }

    let contentType = try MediaType(valid: "application/x-tar")
    let transport = URLSessionTransport(baseURL: "http://example.com")

    let request =
      try await transport.transportRequest(
        spec: OperationSpec.streaming(
          method: .post,
          pathTemplate: "/api",
          body: .file(bodyURL),
          contentTypes: [contentType]
        )
      )

    XCTAssertNil(request.httpBody)
    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.contentType), "application/x-tar")

    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var buffer = [UInt8](repeating: 0, count: 16)
    let count = stream.read(&buffer, maxLength: buffer.count)
    XCTAssertEqual(Data(buffer.prefix(count)), body)
  }

  func testExecutesStreamingOperationWithStreamBody() async throws {

    let body = Data("streamed-request-body".utf8)
    let contentType = try MediaType(valid: "application/x-tar")
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        POST { req, res in
          XCTAssertEqual(req.body, body)
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.contentType), contentType.value)
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.transferEncoding), "chunked")
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(
      baseURL: .init(format: serverURL.absoluteString),
      adapter: RebuildingRequestAdapter()
    )
    let operation: StreamingOperation<Void, URLSessionTransport> =
      Operation(
        transport: transport,
        spec: .streaming(
          method: .post,
          pathTemplate: "/api",
          body: StreamingBody(stream: { InputStream(data: body) }),
          contentTypes: [contentType]
        )
      )

    try await operation.execute()
  }

  func testExecutesStreamingOperationWithAsyncBytesBody() async throws {

    let chunks = [Data("streamed-".utf8), Data("async-".utf8), Data("body".utf8)]
    let body = chunks.reduce(into: Data()) { $0.append($1) }
    let contentType = try MediaType(valid: "application/x-tar")
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        POST { req, res in
          XCTAssertEqual(req.body, body)
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.contentType), contentType.value)
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.transferEncoding), "chunked")
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))
    let operation: StreamingOperation<Void, URLSessionTransport> =
      Operation(
        transport: transport,
        spec: .streaming(
          method: .post,
          pathTemplate: "/api",
          body: StreamingBody.bytes {
            AsyncStream { continuation in
              chunks.forEach { continuation.yield($0) }
              continuation.finish()
            }
          },
          contentTypes: [contentType]
        )
      )

    try await operation.execute()
  }

  func testStreamingAsyncBytesBodyFactoryCanBeReused() async throws {

    let chunks = [Data("first-".utf8), Data("second".utf8)]
    let body = chunks.reduce(into: Data()) { $0.append($1) }
    let contentType = try MediaType(valid: "application/x-tar")
    let requestCount = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        POST { req, res in
          requestCount.withLock { $0 += 1 }
          XCTAssertEqual(req.body, body)
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.transferEncoding), "chunked")
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let factoryCount = Mutex(0)
    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))
    let operation: StreamingOperation<Void, URLSessionTransport> =
      Operation(
        transport: transport,
        spec: .streaming(
          method: .post,
          pathTemplate: "/api",
          body: StreamingBody.bytes {
            factoryCount.withLock { $0 += 1 }
            return AsyncStream { continuation in
              chunks.forEach { continuation.yield($0) }
              continuation.finish()
            }
          },
          contentTypes: [contentType]
        )
      )

    try await operation.execute()
    try await operation.execute()

    XCTAssertGreaterThanOrEqual(factoryCount.withLock { $0 }, 2)
    XCTAssertEqual(requestCount.withLock { $0 }, 2)
  }

  func testExecutesConcurrentStreamingAsyncBytesBodies() async throws {

    let contentType = try MediaType(valid: "application/x-tar")
    let receivedBodies = Mutex<[String]>([])
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        POST { req, res in
          if let data = req.body, let body = String(data: data, encoding: .utf8) {
            receivedBodies.withLock { $0.append(body) }
          }
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.transferEncoding), "chunked")
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0 ..< 8 {
        group.addTask {
          let operation: StreamingOperation<Void, URLSessionTransport> =
            Operation(
              transport: transport,
              spec: .streaming(
                method: .post,
                pathTemplate: "/api",
                body: StreamingBody.bytes {
                  AsyncStream { continuation in
                    continuation.yield(Data("body-\(index)".utf8))
                    continuation.finish()
                  }
                },
                contentTypes: [contentType]
              )
            )

          try await operation.execute()
        }
      }

      try await group.waitForAll()
    }

    XCTAssertEqual(
      receivedBodies.withLock { $0.sorted() },
      (0 ..< 8).map { "body-\($0)" }
    )
  }

  func testStreamingAsyncBytesBodyCanBeReplayedForTemporaryRedirect() async throws {

    try skipIfStreamingBodyReplayIsUnsupported()

    let chunks = [Data("redirected-".utf8), Data("stream".utf8)]
    let body = chunks.reduce(into: Data()) { $0.append($1) }
    let contentType = try MediaType(valid: "application/x-tar")
    let requestCount = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/redirect") {
        POST { _, res in
          requestCount.withLock { $0 += 1 }
          res.send(
            status: .temporaryRedirect,
            headers: [HTTP.StdHeaders.location: ["/api"]],
            body: Data()
          )
        }
      }
      Path("/api") {
        POST { req, res in
          requestCount.withLock { $0 += 1 }
          XCTAssertEqual(req.body, body)
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.transferEncoding), "chunked")
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let factoryCount = Mutex(0)
    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))
    let operation: StreamingOperation<Void, URLSessionTransport> =
      Operation(
        transport: transport,
        spec: .streaming(
          method: .post,
          pathTemplate: "/redirect",
          body: StreamingBody.bytes {
            factoryCount.withLock { $0 += 1 }
            return AsyncStream { continuation in
              chunks.forEach { continuation.yield($0) }
              continuation.finish()
            }
          },
          contentTypes: [contentType]
        )
      )

    try await operation.execute()

    XCTAssertGreaterThanOrEqual(factoryCount.withLock { $0 }, 2)
    XCTAssertEqual(requestCount.withLock { $0 }, 2)
  }

  func testStreamingBodyReplaySurfacesStreamCreationError() async throws {

    try skipIfStreamingBodyReplayIsUnsupported()

    let body = Data("redirected-stream".utf8)
    let contentType = try MediaType(valid: "application/x-tar")
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/redirect") {
        POST { _, res in
          res.send(
            status: .temporaryRedirect,
            headers: [HTTP.StdHeaders.location: ["/api"]],
            body: Data()
          )
        }
      }
      Path("/api") {
        POST { _, res in
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let factoryCount = Mutex(0)
    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))
    let operation: StreamingOperation<Void, URLSessionTransport> =
      Operation(
        transport: transport,
        spec: .streaming(
          method: .post,
          pathTemplate: "/redirect",
          body: StreamingBody(stream: {
            let count = factoryCount.withLock {
              $0 += 1
              return $0
            }
            guard count == 1 else {
              throw StreamingBodyTestError.replayFailed
            }
            return InputStream(data: body)
          }),
          contentTypes: [contentType]
        )
      )

    try await XCTAssertThrowsError(try await operation.execute()) { error in
      guard case StreamingBodyTestError.replayFailed = error else {
        XCTFail("Incorrect Error: \(error)")
        return
      }
    }

    XCTAssertGreaterThanOrEqual(factoryCount.withLock { $0 }, 2)
  }

  private func skipIfStreamingBodyReplayIsUnsupported() throws {

    #if os(watchOS)
    throw XCTSkip("URLSession does not request a replacement body stream for redirected streaming uploads on watchOS.")
    #endif
  }

  func testStreamingAsyncBytesBodyStartsWhenStreamOpens() async throws {

    let state = TrackingByteSequence.State()
    let contentType = try MediaType(valid: "application/x-tar")
    let transport = URLSessionTransport(baseURL: "http://example.com")

    let request = try await transport.transportRequest(
      spec: .streaming(
        method: .post,
        pathTemplate: "/api",
        body: StreamingBody.bytes {
          TrackingByteSequence(chunks: [Data("body".utf8)], state: state)
        },
        contentTypes: [contentType]
      )
    )

    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(state.starts.withLock { $0 }, 0)

    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(state.starts.withLock { $0 }, 1)
  }

  func testExecutesStreamingTransportRequest() async throws {

    let body = Data("manual-streamed-request-body".utf8)
    let contentType = try MediaType(valid: "application/x-tar")
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        POST { req, res in
          XCTAssertEqual(req.body, body)
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.contentType), contentType.value)
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))
    let request = try await transport.transportRequest(
      spec: .streaming(
        method: .post,
        pathTemplate: "/api",
        body: StreamingBody(stream: { InputStream(data: body) }),
        contentTypes: [contentType]
      )
    )

    let response = try await transport.transportResponse(request: request)

    XCTAssertEqual(response.statusCode, 204)
  }

  func testExecutesStreamingTransportRequestWhenAdapterRebuildsRequest() async throws {

    let body = Data("adapter-streamed-request-body".utf8)
    let contentType = try MediaType(valid: "application/x-tar")
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        POST { req, res in
          XCTAssertEqual(req.body, body)
          XCTAssertEqual(req.header(for: HTTP.StdHeaders.contentType), contentType.value)
          XCTAssertEqual(req.header(for: "x-adapted"), "true")
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(
      baseURL: .init(format: serverURL.absoluteString),
      adapter: RebuildingRequestAdapter()
    )
    let request = try await transport.transportRequest(
      spec: .streaming(
        method: .post,
        pathTemplate: "/api",
        body: StreamingBody(stream: { InputStream(data: body) }),
        contentTypes: [contentType]
      )
    )

    let response = try await transport.transportResponse(request: request)

    XCTAssertEqual(response.statusCode, 204)
  }


}


private enum StreamingBodyTestError: Error {
  case replayFailed
}


private struct RebuildingRequestAdapter: RequestAdapter {

  func adapt(transport: some Transport, urlRequest: URLRequest) -> URLRequest {
    var request = URLRequest(url: urlRequest.url!)
    request.httpMethod = urlRequest.httpMethod
    request.allHTTPHeaderFields = urlRequest.allHTTPHeaderFields
    request.setValue("true", forHTTPHeaderField: "x-adapted")
    return request
  }

}


private struct TrackingByteSequence: AsyncSequence, Sendable {

  final class State: @unchecked Sendable {
    let starts = Mutex(0)
  }

  typealias Element = Data

  let chunks: [Data]
  let state: State

  func makeAsyncIterator() -> Iterator {
    state.starts.withLock { $0 += 1 }
    return Iterator(chunks: chunks.makeIterator())
  }

  struct Iterator: AsyncIteratorProtocol {

    var chunks: IndexingIterator<[Data]>

    mutating func next() async throws -> Data? {
      chunks.next()
    }

  }

}
