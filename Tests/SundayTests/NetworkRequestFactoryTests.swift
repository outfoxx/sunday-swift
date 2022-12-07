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
import XCTest

@testable import Sunday
@testable import SundayServer


class NetworkRequestFactoryTests: XCTestCase {


  //
  // MARK: General
  //


  func testEnsureDefaultsCanBeOverridden() {

    let requestFactory = NetworkRequestFactory(
      baseURL: "http://example.com",
      mediaTypeEncoders: MediaTypeEncoders.Builder().build(),
      mediaTypeDecoders: MediaTypeDecoders.Builder().build()
    )

    XCTAssertNil(try? requestFactory.mediaTypeEncoders.find(for: .json))
    XCTAssertNil(try? requestFactory.mediaTypeDecoders.find(for: .json))
  }


  //
  // MARK: Request Building
  //


  func testEncodesQueryParameters() async throws {

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let request =
      try await requestFactory.request(
        method: .get,
        pathTemplate: "/api",
        queryParameters: ["limit": 5, "search": "1 & 2"],
        body: Empty.none
      )

    XCTAssertEqual(request.url?.absoluteString, "http://example.com/api?limit=5&search=1%20%26%202")
  }

  func testFailsWhenNoQueryParamEncoderIsRegisteredAndQueryParamsAreProvided() async throws {

    let requestFactory = NetworkRequestFactory(
      baseURL: "http://example.com",
      mediaTypeEncoders: MediaTypeEncoders.Builder().build()
    )

    try await XCTAssertThrowsError(
      try await requestFactory.request(
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

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let request =
      try await requestFactory.request(
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

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let request =
      try await requestFactory.request(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json, .cbor]
      )

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.accept), "application/json , application/cbor")
  }

  func testFailsIfNoneOfTheAcceptTypesHasADecoder() async throws {

    let requestFactory = NetworkRequestFactory(
      baseURL: "http://example.com",
      mediaTypeDecoders: MediaTypeDecoders.Builder().build()
    )

    try await XCTAssertThrowsError(
      try await requestFactory.request(
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

    let requestFactory = NetworkRequestFactory(
      baseURL: "http://example.com",
      mediaTypeEncoders: MediaTypeEncoders.Builder().build()
    )

    try await XCTAssertThrowsError(
      try await requestFactory.request(
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

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let request =
      try await requestFactory.request(
        method: .post,
        pathTemplate: "/api",
        body: ["a": 5],
        contentTypes: [.json]
      )

    XCTAssertEqual(request.httpBody, #"{"a":5}"#.data(using: .utf8))
  }

  func testSetContentTypeWhenBodyIsNonExistent() async throws {

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let request =
      try await requestFactory.request(
        method: .post,
        pathTemplate: "/api",
        body: Empty.none,
        contentTypes: [.json]
      )

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.contentType), "application/json")
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

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let result: Tester =
      try await requestFactory.result(
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

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await requestFactory.result(
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

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await requestFactory.result(
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
          res.send(status: .ok, headers: headers, body: "[]".data(using: .utf8) ?? Data())
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await requestFactory.result(
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
          res.send(status: .ok, headers: headers, body: "[]".data(using: .utf8) ?? Data())
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await requestFactory.result(
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
          res.send(status: .ok, headers: headers, body: "bad".data(using: .utf8) ?? Data())
        }
      }
    }

    guard let serverURL = server.startLocal(timeout: 5.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    try await XCTAssertThrowsError(
      try await requestFactory.result(
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

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    try await requestFactory.result(
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

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let (data, _) = try await requestFactory.response(
      request: URLRequest(url: try XCTUnwrap(URL(string: "/api", relativeTo: serverURL)))
    )

    XCTAssertEqual(String(data: data ?? Data(), encoding: .utf8), "[]")
  }


  //
  // MARK: Problem Building/Handling
  //


  class TestProblem: Problem {

    static let type = URL(string: "http://example.com/test")!
    static let statusCode = HTTP.StatusCode.badRequest

    let extra: String

    init(extra: String, instance: URL? = nil) {
      self.extra = extra
      super.init(
        type: Self.type,
        title: "Test Problem",
        statusCode: Self.statusCode,
        detail: "A Test Problem",
        instance: instance,
        parameters: nil
      )
    }

    required init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: AnyCodingKey.self)
      extra = try container.decode(String.self, forKey: AnyCodingKey("extra"))
      try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: AnyCodingKey.self)
      try container.encode(extra, forKey: AnyCodingKey("extra"))
      try super.encode(to: encoder)
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    requestFactory.registerProblem(type: TestProblem.type, problemType: TestProblem.self)

    do {
      try await requestFactory.result(
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
        XCTAssertEqual(problem.type, problem.type)
        XCTAssertEqual(problem.title, problem.title)
        XCTAssertEqual(problem.status, problem.status)
        XCTAssertEqual(problem.detail, problem.detail)
        XCTAssertEqual(problem.instance, problem.instance)
        XCTAssertNil(problem.parameters)
        XCTAssertEqual(problem.extra, problem.extra)
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    do {
      try await requestFactory.result(
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
      XCTAssertTrue(type(of: error) == Problem.self, "Error is not a Problem")
      if let problem = error as? Problem {
        XCTAssertEqual(problem.type, problem.type)
        XCTAssertEqual(problem.title, problem.title)
        XCTAssertEqual(problem.status, problem.status)
        XCTAssertEqual(problem.detail, problem.detail)
        XCTAssertEqual(problem.instance, problem.instance)
        XCTAssertEqual(problem.parameters?["extra"], problem.parameters?["extra"])
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    do {
      try await requestFactory.result(
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
      XCTAssertTrue(type(of: error) == Problem.self, "Error is not a Problem")
      if let problem = error as? Problem {
        XCTAssertEqual(problem.type, problem.type)
        XCTAssertEqual(problem.title, problem.title)
        XCTAssertEqual(problem.status, problem.status)
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    do {
      try await requestFactory.result(
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
      XCTAssertTrue(type(of: error) == Problem.self, "Error is not a Problem")
      if let problem = error as? Problem {
        XCTAssertEqual(problem.type, problem.type)
        XCTAssertEqual(problem.title, problem.title)
        XCTAssertEqual(problem.status, problem.status)
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL, mediaTypeDecoders: MediaTypeDecoders.Builder().build())
    defer { requestFactory.close() }

    do {
      try await requestFactory.result(
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    requestFactory.registerProblem(type: TestProblem.type, problemType: TestProblem.self)

    do {
      let result =
        try await nilifyResponse(statuses: [], problemTypes: [TestProblem.self]) {
          try await requestFactory.result(
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    requestFactory.registerProblem(type: TestProblem.type, problemType: TestProblem.self)

    do {
      let result =
        try await nilifyResponse(statusCodes: [TestProblem.statusCode], problemTypes: []) {
          try await requestFactory.result(
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

  func testEventSourceBuilding() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/events") {
        GET { _, res in
          res.start(status: .ok, headers: [
            HTTP.StdHeaders.contentType: [MediaType.eventStream.value],
            HTTP.StdHeaders.transferEncoding: ["chunked"],
          ])
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(100)) {
            res.send(chunk: "event: test\n".data(using: .utf8) ?? Data())
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(200)) {
            res.send(chunk: "id: 123\n".data(using: .utf8) ?? Data())
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(300)) {
            res.send(chunk: "data: {\"some\":\r".data(using: .utf8) ?? Data())
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(400)) {
            res.send(chunk: "data: \"test data\"}\n\n".data(using: .utf8) ?? Data())
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let eventSource = requestFactory.eventSource(
      method: .get,
      pathTemplate: "/events",
      pathParameters: nil,
      queryParameters: nil,
      body: Empty.none,
      contentTypes: [.json],
      acceptTypes: [.json],
      headers: nil
    )

    eventSource.addEventListener(for: "test") { _, _, _ in
      eventSource.close()
      completeX.fulfill()
    }

    eventSource.connect()

    waitForExpectations { _ in
      eventSource.close()
    }
  }

  func testEventStreamBuilding() async throws {

    struct TestEvent: Codable {
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
            res.send(chunk: "event: test\n".data(using: .utf8) ?? Data())
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(200)) {
            res.send(chunk: "id: 123\n".data(using: .utf8) ?? Data())
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(300)) {
            res.send(chunk: "data: {\"some\":\r".data(using: .utf8) ?? Data())
          }
          res.server.queue.asyncAfter(deadline: .now() + .milliseconds(400)) {
            res.send(chunk: "data: \"test data\"}\n\n".data(using: .utf8) ?? Data())
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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let eventStream =
      requestFactory.eventStream(
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

    var eventStreamIter = eventStream.makeAsyncIterator()
    let event = await eventStreamIter.next()
    XCTAssertNotNil(event, "no event returned")
    XCTAssertEqual(event!.some, "test data")

    // Ensure closing factory is gracefully handled by spawned EventSource
    requestFactory.close()

    try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))
  }

}
