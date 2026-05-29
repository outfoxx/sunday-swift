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

import PotentCodables
import Synchronization
import XCTest

@testable import Sunday
@testable import SundayServer


class URLSessionTransportTests: XCTestCase {


  //
  // MARK: General
  //


  func testEnsureDefaultsCanBeOverridden() {

    let transport = URLSessionTransport(
      baseURL: "http://example.com",
      mediaTypeEncoders: MediaTypeEncoders.Builder().build(),
      mediaTypeDecoders: MediaTypeDecoders.Builder().build()
    )

    XCTAssertNil(try? transport.mediaTypeEncoders.find(for: .json))
    XCTAssertNil(try? transport.mediaTypeDecoders.find(for: .json))
  }

  func testCanUseProvidedSessionForEvents() {

    let session = URLSession(configuration: .ephemeral)
    let transport = URLSessionTransport(baseURL: "http://example.com", session: session, eventSession: session)

    XCTAssertTrue(transport.eventSession === session)
    transport.close()
  }

  func testUsesExplicitEventSessionWhenProvided() {

    let session = URLSession(configuration: .ephemeral)
    let eventSession = URLSession(configuration: .ephemeral)
    let transport = URLSessionTransport(baseURL: "http://example.com", session: session, eventSession: eventSession)

    XCTAssertTrue(transport.eventSession === eventSession)
    XCTAssertFalse(transport.eventSession === session)
    transport.close()
  }


  //
  // MARK: Request Building
  //


  func testEncodesQueryParameters() async throws {

    let transport = URLSessionTransport(baseURL: "http://example.com")

    let request =
      try await transport.transportRequest(
        method: .get,
        pathTemplate: "/api",
        queryParameters: ["limit": 5, "search": "1 & 2"],
        body: Empty.none
      )

    XCTAssertEqual(request.url?.absoluteString, "http://example.com/api?limit=5&search=1%20%26%202")
  }

  func testFailsWhenNoQueryParamEncoderIsRegisteredAndQueryParamsAreProvided() async throws {

    let transport = URLSessionTransport(
      baseURL: "http://example.com",
      mediaTypeEncoders: MediaTypeEncoders.Builder().build()
    )

    try await XCTAssertThrowsError(
      try await transport.transportRequest(
        method: .get,
        pathTemplate: "/api",
        queryParameters: ["limit": 5, "search": "1 & 2"],
        body: Empty.none
      )
    ) { error in
      guard
        case SundayError.requestEncodingFailed(reason: let reason) = error,
        case RequestEncodingFailureReason.unsupportedContentType = reason
      else {
        XCTFail("Incorrect Error")
        return
      }
    }
  }

  func testAddsCustomHeaders() async throws {

    let transport = URLSessionTransport(baseURL: "http://example.com")

    let request =
      try await transport.transportRequest(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        headers: [
          HTTP.StdHeaders.authorization: ["Bearer 12345", "Bearer 67890"],
          HTTP.StdHeaders.accept: [MediaType.json, MediaType.cbor],
        ]
      )

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 12345,Bearer 67890")
    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.accept), "application/json,application/cbor")
  }

  func testAddsAcceptHeader() async throws {

    let transport = URLSessionTransport(baseURL: "http://example.com")

    let request =
      try await transport.transportRequest(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json, .cbor]
      )

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.accept), "application/json , application/cbor")
  }

  func testFailsIfNoneOfTheAcceptTypesHasADecoder() async throws {

    let transport = URLSessionTransport(
      baseURL: "http://example.com",
      mediaTypeDecoders: MediaTypeDecoders.Builder().build()
    )

    try await XCTAssertThrowsError(
      try await transport.transportRequest(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json, .cbor]
      )
    ) { error in
      guard
        case SundayError.requestEncodingFailed(reason: let reason) = error,
        case RequestEncodingFailureReason.noSupportedAcceptTypes = reason
      else {
        XCTFail("Incorrect Error")
        return
      }
    }
  }

  func testFailsIfNoneOfTheContentTypesHasAnEncoder() async throws {

    let transport = URLSessionTransport(
      baseURL: "http://example.com",
      mediaTypeEncoders: MediaTypeEncoders.Builder().build()
    )

    try await XCTAssertThrowsError(
      try await transport.transportRequest(
        method: .get,
        pathTemplate: "/api",
        body: "a body",
        contentTypes: [.json, .cbor]
      )
    ) { error in
      guard
        case SundayError.requestEncodingFailed(reason: let reason) = error,
        case RequestEncodingFailureReason.noSupportedContentTypes = reason
      else {
        XCTFail("Incorrect Error")
        return
      }
    }
  }

  func testAttachesBodyEncodedByContentType() async throws {

    let transport = URLSessionTransport(baseURL: "http://example.com")

    let request =
      try await transport.transportRequest(
        method: .post,
        pathTemplate: "/api",
        body: ["a": 5],
        contentTypes: [.json]
      )

    XCTAssertEqual(request.httpBody, Data(#"{"a":5}"#.utf8))
  }

  func testSetContentTypeWhenBodyIsNonExistent() async throws {

    let transport = URLSessionTransport(baseURL: "http://example.com")

    let request =
      try await transport.transportRequest(
        method: .post,
        pathTemplate: "/api",
        body: Empty.none,
        contentTypes: [.json]
      )

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.contentType), "application/json")
  }

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

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))
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


  //
  // MARK: Response/Result Processing
  //

  func testFetchesTypedResults() async throws {

    struct Tester: Codable, Equatable, Hashable {
      let name: String
      let count: Int
    }

    let tester = Tester(name: "test", count: 5)

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/api") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.json.value]]
            res.send(statusCode: .ok, headers: headers, value: tester)
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    let result: Tester =
      try await transport.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      )

    XCTAssertEqual(result, tester)
  }

  func testFailsWhenNoDataAndNonEmptyResult() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/api") {
          GET { _, res in
            res.send(statusCode: .noContent)
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await transport.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as [String]
    ) { error in
      guard case SundayError.unexpectedEmptyResponse = error else {
        return XCTFail("unexected error")
      }
    }
  }

  func testFailsWhenResultExpectedAndNoDataInResponse() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/api") {
          GET { _, res in
            res.send(statusCode: .ok, body: Data())
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await transport.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as [String]
    ) { error in
      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.noData = reason
      else {
        return XCTFail("unexected error")
      }
    }
  }

  func testFailsWhenResponseContentTypeIsInvalid() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        GET { _, res in
          let headers = [HTTP.StdHeaders.contentType: ["bad/x-unknown"]]
          res.send(status: .ok, headers: headers, body: Data("[]".utf8))
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await transport.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as [String]
    ) { error in
      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.invalidContentType = reason
      else {
        return XCTFail("unexected error")
      }
    }
  }

  func testFailsWhenResponseContentTypeIsUnsupported() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        GET { _, res in
          let headers = [HTTP.StdHeaders.contentType: ["application/x-unknown"]]
          res.send(status: .ok, headers: headers, body: Data("[]".utf8))
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await transport.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as [String]
    ) { error in
      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.unsupportedContentType = reason
      else {
        return XCTFail("unexected error")
      }
    }
  }

  func testFailsWhenResponseDeserializationFails() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        GET { _, res in
          let headers = [HTTP.StdHeaders.contentType: [MediaType.json.value]]
          res.send(status: .ok, headers: headers, body: Data("bad".utf8))
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await transport.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as [String]
    ) { error in
      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.deserializationFailed = reason
      else {
        return XCTFail("unexected error")
      }
    }
  }

  func testExecutesRequestsWithNoDataResponse() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
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

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    try await transport.result(
      method: .post,
      pathTemplate: "/api",
      pathParameters: nil,
      queryParameters: nil,
      body: Empty.none,
      contentTypes: nil,
      acceptTypes: nil,
      headers: nil
    )
  }

  func testExecutesManualRequestsForResponses() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/api") {
          GET { _, res in
            res.send(statusCode: .ok, text: "[]")
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let transport = URLSessionTransport(baseURL: .init(format: serverURL.absoluteString))

    let response = try await transport.transportResponse(
      request: URLRequest(url: try XCTUnwrap(URL(string: "/api", relativeTo: serverURL)))
    )

    XCTAssertEqual(response.statusCode, 200)
  }


  //
  // MARK: Problem Building/Handling
  //


  struct TestProblem: Problem {

    static let typeURL = URL(string: "http://example.com/test")!
    static let statusCode = HTTP.StatusCode.badRequest

    let type: URL
    let title: String
    let status: Int
    let detail: String?
    let instance: URL?
    let parameters: [String: AnyValue]?
    let extra: String

    init(extra: String, instance: URL? = nil) {
      self.type = Self.typeURL
      self.title = "Test Problem"
      self.status = Self.statusCode.rawValue
      self.detail = "A Test Problem"
      self.instance = instance
      self.parameters = nil
      self.extra = extra
    }

    init(from decoder: Decoder) throws {
      let problem = try GenericProblem(from: decoder)
      let container = try decoder.container(keyedBy: AnyCodingKey.self)
      self.type = problem.type
      self.title = problem.title
      self.status = problem.status
      self.detail = problem.detail
      self.instance = problem.instance
      self.parameters = nil
      self.extra = try container.decode(String.self, forKey: AnyCodingKey("extra"))
    }

    func encode(to encoder: Encoder) throws {
      let problem = GenericProblem(
        type: type,
        title: title,
        status: status,
        detail: detail,
        instance: instance,
        parameters: parameters
      )
      try problem.encode(to: encoder)
      var container = encoder.container(keyedBy: AnyCodingKey.self)
      try container.encode(extra, forKey: AnyCodingKey("extra"))
    }

  }

  func testRegisteredProblemsDecodeAsTypedProblems() async throws {

    let testProblem = TestProblem(extra: "Something Extra", instance: URL(string: "id:12345"))

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/problem") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(statusCode: TestProblem.statusCode, headers: headers, value: testProblem)
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL)
    defer { transport.close() }

    ProblemRegistration(type: TestProblem.typeURL, problemType: TestProblem.self).register(on: transport)

    do {
      try await transport.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      XCTFail("Request should have thrown problem")
    }
    catch {
      XCTAssertTrue(type(of: error) == TestProblem.self, "\(error) is not a TestProblem")
      if let problem = error as? TestProblem {
        XCTAssertEqual(problem.type, testProblem.type)
        XCTAssertEqual(problem.title, testProblem.title)
        XCTAssertEqual(problem.status, testProblem.status)
        XCTAssertEqual(problem.detail, testProblem.detail)
        XCTAssertEqual(problem.instance, testProblem.instance)
        XCTAssertNil(problem.parameters)
        XCTAssertEqual(problem.extra, testProblem.extra)
      }
    }
  }

  func testUnregisteredProblemsDecodeAsGenericProblems() async throws {

    let testProblem = TestProblem(extra: "Something Extra", instance: URL(string: "id:12345"))

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/problem") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(statusCode: TestProblem.statusCode, headers: headers, value: testProblem)
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL)
    defer { transport.close() }

    do {
      try await transport.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      XCTFail("Request should have thrown problem")
    }
    catch {
      XCTAssertTrue(type(of: error) == GenericProblem.self, "\(error) is not a GenericProblem")
      if let problem = error as? GenericProblem {
        XCTAssertEqual(problem.type, testProblem.type)
        XCTAssertEqual(problem.title, testProblem.title)
        XCTAssertEqual(problem.status, testProblem.status)
        XCTAssertEqual(problem.detail, testProblem.detail)
        XCTAssertEqual(problem.instance, testProblem.instance)
        XCTAssertEqual(problem.parameters?["extra"], AnyValue.string(testProblem.extra))
      }
    }
  }

  func testNonProblemErrorResponsesAreTranslatedIntoStandardProblems() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/problem") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.html.value]]
            res.send(status: .badRequest, headers: headers, value: "<error>Error</error>")
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL)
    defer { transport.close() }

    do {
      try await transport.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      XCTFail("Request should have thrown problem")
    }
    catch {
      XCTAssertTrue(type(of: error) == HTTP.StatusProblem.self, "\(error) is not a StatusProblem")
      if let problem = error as? HTTP.StatusProblem {
        XCTAssertEqual(problem.type, URL(string: "about:blank"))
        XCTAssertEqual(problem.title, HTTP.statusText[.badRequest])
        XCTAssertEqual(problem.status, HTTP.StatusCode.badRequest.rawValue)
        XCTAssertNil(problem.detail)
        XCTAssertNil(problem.instance)
        XCTAssertNil(problem.parameters)
      }
    }
  }

  func testResponseProblemsWithNoDataAreTranslatedIntoStandardProblems() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/problem") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(status: .badRequest, headers: headers, body: Data())
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL)
    defer { transport.close() }

    do {
      try await transport.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      XCTFail("Request should have thrown problem")
    }
    catch {
      XCTAssertTrue(type(of: error) == HTTP.StatusProblem.self, "\(error) is not a StatusProblem")
      if let problem = error as? HTTP.StatusProblem {
        XCTAssertEqual(problem.type, URL(string: "about:blank"))
        XCTAssertEqual(problem.title, HTTP.statusText[.badRequest])
        XCTAssertEqual(problem.status, HTTP.StatusCode.badRequest.rawValue)
        XCTAssertNil(problem.detail)
        XCTAssertNil(problem.instance)
        XCTAssertNil(problem.parameters)
      }
    }
  }

  func testResponseProblemsFailWhenNoJSONDecoder() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/problem") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(statusCode: TestProblem.statusCode, headers: headers, value: TestProblem(extra: "none"))
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL, mediaTypeDecoders: MediaTypeDecoders.Builder().build())
    defer { transport.close() }

    do {
      try await transport.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      XCTFail("Request should have thrown problem")
    }
    catch {
      XCTAssertTrue(type(of: error) == SundayError.self, "Error is not a SundayError")
    }
  }

  func testNilifyResponseWorksWithProblemTypess() async throws {

    let testProblem = TestProblem(extra: "Something Extra", instance: URL(string: "id:12345"))


    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/problem") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(statusCode: TestProblem.statusCode, headers: headers, value: testProblem)
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL)
    defer { transport.close() }

    transport.registerProblem(type: TestProblem.typeURL, problemType: TestProblem.self)

    do {
      let result =
        try await nilifyResponse(statuses: [], problemTypes: [TestProblem.self]) {
          try await transport.result(
            method: .get,
            pathTemplate: "problem",
            pathParameters: nil,
            queryParameters: nil,
            body: Empty.none,
            contentTypes: [.json],
            acceptTypes: [.json],
            headers: nil
          ) as String
        }
      XCTAssertNil(result)
    }
    catch {
      XCTFail("Should have returned nil")
    }
  }

  func testNilifyResponseWorksWithStatusCodes() async throws {

    let testProblem = TestProblem(extra: "Something Extra", instance: URL(string: "id:12345"))


    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/problem") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(statusCode: TestProblem.statusCode, headers: headers, value: testProblem)
          }
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL)
    defer { transport.close() }

    transport.registerProblem(type: TestProblem.typeURL, problemType: TestProblem.self)

    do {
      let result =
        try await nilifyResponse(statusCodes: [TestProblem.statusCode], problemTypes: []) {
          try await transport.result(
            method: .get,
            pathTemplate: "problem",
            pathParameters: nil,
            queryParameters: nil,
            body: Empty.none,
            contentTypes: [.json],
            acceptTypes: [.json],
            headers: nil
          ) as String
        }
      XCTAssertNil(result)
    }
    catch {
      XCTFail("Should have returned nil")
    }
  }

  //
  // MARK: Event Source/Stream Building
  //

  func testEventSourceDoesNotRetainTransport() {

    weak var weakTransport: URLSessionTransport?

    do {
      let transport = URLSessionTransport(baseURL: "http://example.com")
      weakTransport = transport

      _ = transport.eventSource(
        method: .get,
        pathTemplate: "/events",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
    }

    XCTAssertNil(weakTransport)
  }

  func testDirectEventSourceIsNotRetainedByTransport() {

    let transport = URLSessionTransport(baseURL: "http://example.com")
    defer { transport.close() }

    weak var weakEventSource: EventSource?

    do {
      let eventSource = transport.eventSource(
        method: .get,
        pathTemplate: "/events",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      weakEventSource = eventSource
    }

    XCTAssertNil(weakEventSource)
  }

  func testEventStreamDoesNotRetainTransport() {

    weak var weakTransport: URLSessionTransport?

    do {
      let transport = URLSessionTransport(baseURL: "http://example.com")
      weakTransport = transport

      _ =
        transport.eventStream(
          method: .get,
          pathTemplate: "/events",
          pathParameters: nil,
          queryParameters: nil,
          body: Empty.none,
          contentTypes: [.json],
          acceptTypes: [.json],
          headers: nil,
          decoder: { _, _, _, _, _ in "unexpected" }
        ) as AsyncStream<String>
    }

    XCTAssertNil(weakTransport)
  }

  func testEventStreamCancellationBeforeSetupDoesNotStartConnection() async throws {

    let requestX = expectation(description: "event stream request should not be built")
    requestX.isInverted = true

    let transport = URLSessionTransport(baseURL: "http://example.com")
    defer { transport.close() }

    let eventStream =
      transport.eventStream(
        decoder: { _, _, _, _, _ in "unexpected" },
        from: {
          try await Task.sleep(for: .milliseconds(200))
          requestX.fulfill()
          return nil
        }
      ) as AsyncStream<String>

    let consumeTask = Task {
      var iterator = eventStream.makeAsyncIterator()
      _ = await iterator.next()
    }

    consumeTask.cancel()
    _ = await consumeTask.result

    await fulfillment(of: [requestX], timeout: 0.4)
  }

  func testEventStreamTransportCloseBeforeSetupDoesNotStartConnection() async throws {

    let requestX = expectation(description: "event stream request should not be built")
    requestX.isInverted = true
    let consumeX = expectation(description: "event stream should finish")

    let transport = URLSessionTransport(baseURL: "http://example.com")

    let eventStream =
      transport.eventStream(
        decoder: { _, _, _, _, _ in "unexpected" },
        from: {
          try await Task.sleep(for: .milliseconds(200))
          requestX.fulfill()
          return nil
        }
      ) as AsyncStream<String>

    let consumeTask = Task {
      var iterator = eventStream.makeAsyncIterator()
      _ = await iterator.next()
      consumeX.fulfill()
    }

    transport.close()

    await fulfillment(of: [consumeX], timeout: 1.0)
    consumeTask.cancel()
    _ = await consumeTask.result
    await fulfillment(of: [requestX], timeout: 0.4)
  }

  func testEventStreamSetupClosesEventSourceWhenCancelledAfterConnect() async throws {

    let jsonDecoder = try XCTUnwrap(MediaTypeDecoders.default.find(for: .json) as? TextMediaTypeDecoder)
    let shouldCancelCallCount = Mutex(0)
    let setup = URLSessionTransportEventStreamSetup()
    let eventSource =
      EventSource { _ in
        URLSession.DataEventStream(events: AsyncThrowingStream { _ in })
      }

    let eventStream =
      AsyncStream(String.self) { continuation in
        let setupTask =
          setup.start(
            eventSource: eventSource,
            continuation: continuation,
            shouldCancel: {
              shouldCancelCallCount.withLock { callCount in
                callCount += 1
                return callCount >= 4
              }
            },
            jsonDecoder: jsonDecoder,
            decoder: { _, _, _, _, _ in "unexpected" }
          )
        setup.store(task: setupTask)
      }

    var iterator = eventStream.makeAsyncIterator()
    let result = await iterator.next()

    XCTAssertNil(result)
    let readyState = await eventSource.readyState
    XCTAssertEqual(readyState, .closed)
  }

  @MainActor
  func testEventSourceBuilding() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(100)) {
            res.send(chunk: Data("event: test\n".utf8))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(200)) {
            res.send(chunk: Data("id: 123\n".utf8))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(300)) {
            res.send(chunk: Data("data: {\"some\":\r".utf8))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(400)) {
            res.send(chunk: Data("data: \"test data\"}\n\n".utf8))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(500)) {
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

    let completeX = expectation(description: "event source building - complete")

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL)
    defer { transport.close() }

    let eventSource = transport.eventSource(
      method: .get,
      pathTemplate: "/events",
      pathParameters: nil,
      queryParameters: nil,
      body: Empty.none,
      contentTypes: [.json],
      acceptTypes: [.json],
      headers: nil
    )

    await eventSource.addEventListener(for: "test") { _, _, _ in
      Task { await eventSource.close() }
      completeX.fulfill()
    }

    await eventSource.connect()

    await fulfillment(of: [completeX], timeout: 30)
    await eventSource.close()
  }

  func testEventStreamBuilding() async throws {

    enum Timeout: Error {
      case expired
    }

    struct TestEvent: Codable, Sendable {
      var some: String
    }

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(100)) {
            res.send(chunk: Data("event: test\n".utf8))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(200)) {
            res.send(chunk: Data("id: 123\n".utf8))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(300)) {
            res.send(chunk: Data("data: {\"some\":\r".utf8))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(400)) {
            res.send(chunk: Data("data: \"test data\"}\n\n".utf8))
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(500)) {
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

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let transport = URLSessionTransport(baseURL: baseURL)
    defer { transport.close() }

    let eventStream =
      transport.eventStream(
        method: .get,
        pathTemplate: "/events",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil,
        decoder: { decoder, event, _, data, log in
          switch event {
          case "test": return try decoder.decode(TestEvent.self, from: data)
          default:
            log.error("Unsupported event type")
            return nil
          }
        }
      ) as AsyncStream<TestEvent>

    let result = try await withThrowingTaskGroup(of: [TestEvent].self) { group in
      group.addTask {
        var iterator = eventStream.makeAsyncIterator()
        var events: [TestEvent] = []
        if let event = await iterator.next() {
          events.append(event)
        }

        // Ensure closing transport is gracefully handled by spawned EventSource
        transport.close()

        if let event = await iterator.next() {
          events.append(event)
        }
        return events
      }
      group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw Timeout.expired
      }

      let result = try await group.next()!
      group.cancelAll()
      return result
    }

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.some, "test data")
  }

  func testEventStreamFinishesWhenEventSourceCloses() async throws {

    enum Timeout: Error {
      case expired
    }

    let transport = URLSessionTransport(baseURL: "http://example.com")
    defer { transport.close() }

    let eventStream =
      transport.eventStream(
        decoder: { _, _, _, _, _ in "unexpected" },
        from: { nil }
      ) as AsyncStream<String>

    let result = try await withThrowingTaskGroup(of: String?.self) { group in
      group.addTask {
        var iterator = eventStream.makeAsyncIterator()
        return await iterator.next()
      }
      group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw Timeout.expired
      }

      let result = try await group.next()!
      group.cancelAll()
      return result
    }

    XCTAssertNil(result)
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
