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

import Combine
import CombineExpectations
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


  func testEncodesQueryParameters() throws {

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let requestRecorder =
      requestFactory.request(
        method: .get,
        pathTemplate: "/api",
        queryParameters: ["limit": 5, "search": "1 & 2"],
        body: Empty.none
      )
      .record()

    let request = try wait(for: requestRecorder.single, timeout: 1.0)

    XCTAssertEqual(request.url?.absoluteString, "http://example.com/api?limit=5&search=1%20%26%202")
  }

  func testFailsWhenNoQueryParamEncoderIsRegisteredAndQueryParamsAreProvided() throws {

    let requestFactory = NetworkRequestFactory(
      baseURL: "http://example.com",
      mediaTypeEncoders: MediaTypeEncoders.Builder().build()
    )

    let requestRecorder =
      requestFactory.request(
        method: .get,
        pathTemplate: "/api",
        queryParameters: ["limit": 5, "search": "1 & 2"],
        body: Empty.none
      )
      .record()

    XCTAssertThrowsError(try wait(for: requestRecorder.single, timeout: 1.0)) { error in
      guard
        case SundayError.requestEncodingFailed(reason: let reason) = error,
        case RequestEncodingFailureReason.unsupportedContentType = reason
      else {
        XCTFail("Incorrect Error")
        return
      }
    }
  }

  func testAddsCustomHeaders() throws {

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let requestRecorder =
      requestFactory.request(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        headers: [
          HTTP.StdHeaders.authorization: ["Bearer 12345", "Bearer 67890"],
          HTTP.StdHeaders.accept: [MediaType.json, MediaType.cbor],
        ]
      )
      .record()

    let request = try wait(for: requestRecorder.single, timeout: 1.0)

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 12345,Bearer 67890")
    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.accept), "application/json,application/cbor")
  }

  func testAddsAcceptHeader() throws {

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let requestRecorder =
      requestFactory.request(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json, .cbor]
      )
      .record()

    let request = try wait(for: requestRecorder.single, timeout: 1.0)

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.accept), "application/json , application/cbor")
  }

  func testFailsIfNoneOfTheAcceptTypesHasADecoder() throws {

    let requestFactory = NetworkRequestFactory(
      baseURL: "http://example.com",
      mediaTypeDecoders: MediaTypeDecoders.Builder().build()
    )

    let requestRecorder =
      requestFactory.request(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json, .cbor]
      )
      .record()

    XCTAssertThrowsError(try wait(for: requestRecorder.single, timeout: 1.0)) { error in
      guard
        case SundayError.requestEncodingFailed(reason: let reason) = error,
        case RequestEncodingFailureReason.noSupportedAcceptTypes = reason
      else {
        XCTFail("Incorrect Error")
        return
      }
    }
  }

  func testFailsIfNoneOfTheContentTypesHasAnEncoder() throws {

    let requestFactory = NetworkRequestFactory(
      baseURL: "http://example.com",
      mediaTypeEncoders: MediaTypeEncoders.Builder().build()
    )

    let requestRecorder =
      requestFactory.request(
        method: .get,
        pathTemplate: "/api",
        body: "a body",
        contentTypes: [.json, .cbor]
      )
      .record()

    XCTAssertThrowsError(try wait(for: requestRecorder.single, timeout: 1.0)) { error in
      guard
        case SundayError.requestEncodingFailed(reason: let reason) = error,
        case RequestEncodingFailureReason.noSupportedContentTypes = reason
      else {
        XCTFail("Incorrect Error")
        return
      }
    }
  }

  func testAttachesBodyEncodedByContentType() throws {

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let requestRecorder =
      requestFactory.request(
        method: .post,
        pathTemplate: "/api",
        body: ["a": 5],
        contentTypes: [.json]
      )
      .record()

    let request = try wait(for: requestRecorder.single, timeout: 1.0)

    XCTAssertEqual(request.httpBody, #"{"a":5}"#.data(using: .utf8))
  }

  func testSetContentTypeWhenBodyIsNonExistent() throws {

    let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")

    let requestRecorder =
      requestFactory.request(
        method: .post,
        pathTemplate: "/api",
        body: Empty.none,
        contentTypes: [.json]
      )
      .record()

    let request = try wait(for: requestRecorder.single, timeout: 1.0)

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.contentType), "application/json")
  }


  //
  // MARK: Response/Result Processing
  //

  func testFetchesTypedResults() throws {

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

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let resultRecorder =
      (requestFactory.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as RequestResultPublisher<Tester>)
      .record()

    let result = try wait(for: resultRecorder.single, timeout: 1.0)

    XCTAssertEqual(result, tester)
  }

  func testFailsWhenNoDataAndNonEmptyResult() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/api") {
          GET { _, res in
            res.send(statusCode: .noContent)
          }
        }
      }
    }

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let resultRecorder =
      (requestFactory.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as RequestResultPublisher<[String]>)
      .record()

    XCTAssertThrowsError(try wait(for: resultRecorder.single, timeout: 1.0)) { error in

      guard case SundayError.unexpectedEmptyResponse = error else {
        return XCTFail("unexected error")
      }

    }
  }

  func testFailsWhenResultExpectedAndNoDataInResponse() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/api") {
          GET { _, res in
            res.send(statusCode: .ok, body: Data())
          }
        }
      }
    }

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let resultRecorder =
      (requestFactory.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as RequestResultPublisher<[String]>)
      .record()

    XCTAssertThrowsError(try wait(for: resultRecorder.single, timeout: 1.0)) { error in

      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.noData = reason
      else {
        return XCTFail("unexected error")
      }

    }
  }

  func testFailsWhenResponseContentTypeIsInvalid() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        GET { _, res in
          let headers = [HTTP.StdHeaders.contentType: ["bad/x-unknown"]]
          res.send(status: .ok, headers: headers, body: "[]".data(using: .utf8) ?? Data())
        }
      }
    }

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let resultRecorder =
      (requestFactory.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as RequestResultPublisher<[String]>)
      .record()

    XCTAssertThrowsError(try wait(for: resultRecorder.single, timeout: 1.0)) { error in

      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.invalidContentType = reason
      else {
        return XCTFail("unexected error")
      }

    }
  }

  func testFailsWhenResponseContentTypeIsUnsupported() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        GET { _, res in
          let headers = [HTTP.StdHeaders.contentType: ["application/x-unknown"]]
          res.send(status: .ok, headers: headers, body: "[]".data(using: .utf8) ?? Data())
        }
      }
    }

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let resultRecorder =
      (requestFactory.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as RequestResultPublisher<[String]>)
      .record()

    XCTAssertThrowsError(try wait(for: resultRecorder.single, timeout: 1.0)) { error in

      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.unsupportedContentType = reason
      else {
        return XCTFail("unexected error")
      }

    }
  }

  func testFailsWhenResponseDeserializationFails() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        GET { _, res in
          let headers = [HTTP.StdHeaders.contentType: [MediaType.json.value]]
          res.send(status: .ok, headers: headers, body: "bad".data(using: .utf8) ?? Data())
        }
      }
    }

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let resultRecorder =
      (requestFactory.result(
        method: .get,
        pathTemplate: "/api",
        body: Empty.none,
        acceptTypes: [.json]
      ) as RequestResultPublisher<[String]>)
      .record()

    XCTAssertThrowsError(try wait(for: resultRecorder.single, timeout: 1.0)) { error in

      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.deserializationFailed = reason
      else {
        return XCTFail("unexected error")
      }

    }
  }

  func testExecutesRequestsWithNoDataResponse() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/api") {
        POST { _, res in
          res.send(statusCode: .noContent)
        }
      }
    }

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let resultRecorder = requestFactory
      .result(
        method: .post,
        pathTemplate: "/api",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: nil,
        acceptTypes: nil,
        headers: nil
      )
      .record()

    _ = try wait(for: resultRecorder.single, timeout: 1.0)
  }

  func testExecutesManualRequestsForResponses() throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/api") {
          GET { _, res in
            res.send(statusCode: .ok, text: "[]")
          }
        }
      }
    }

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let requestFactory = NetworkRequestFactory(baseURL: .init(format: serverURL.absoluteString))

    let resultRecorder =
      requestFactory.response(request: URLRequest(url: try XCTUnwrap(URL(string: "/api", relativeTo: serverURL))))
        .record()

    let result = try wait(for: resultRecorder.single, timeout: 1.0)

    XCTAssertEqual(String(data: result.data ?? Data(), encoding: .utf8), "[]")
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

  func testRegisteredProblemsDecodeAsTypedProblems() throws {

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

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let completeX = expectation(description: "typed problem - complete")

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    requestFactory.registerProblem(type: TestProblem.type, problemType: TestProblem.self)

    let requestCancel =
      requestFactory.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      .sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
            XCTAssertTrue(type(of: error) == TestProblem.self, "Error is not a TestProblem")
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
          else {
            XCTFail("Request should have thrown problem")
          }
          completeX.fulfill()
        },
        receiveValue: { _ in }
      )

    waitForExpectations(timeout: 5.0) { _ in
      requestCancel.cancel()
    }
  }

  func testUnregisteredProblemsDecodeAsGenericProblems() throws {

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

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let completeX = expectation(description: "typed problem - complete")

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let requestCancel =
      requestFactory.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      .sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
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
          else {
            XCTFail("Request should have thrown problem")
          }
          completeX.fulfill()
        },
        receiveValue: { _ in }
      )

    waitForExpectations(timeout: 5.0) { _ in
      requestCancel.cancel()
    }
  }

  func testNonProblemErrorResponsesAreTranslatedIntoStandardProblems() throws {

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

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let completeX = expectation(description: "typed problem - complete")

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let requestCancel =
      requestFactory.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      .sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
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
          else {
            XCTFail("Request should have thrown problem")
          }
          completeX.fulfill()
        },
        receiveValue: { _ in }
      )

    waitForExpectations(timeout: 5.0) { _ in
      requestCancel.cancel()
    }
  }

  func testResponseProblemsWithNoDataAreTranslatedIntoStandardProblems() throws {

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

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let completeX = expectation(description: "typed problem - complete")

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let requestCancel =
      requestFactory.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      .sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
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
          else {
            XCTFail("Request should have thrown problem")
          }
          completeX.fulfill()
        },
        receiveValue: { _ in }
      )

    waitForExpectations(timeout: 5.0) { _ in
      requestCancel.cancel()
    }
  }

  func testResponseProblemsFailWhenNoJSONDecoder() throws {

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

    guard let serverURL = server.start(timeout: 2.0) else {
      XCTFail("could not start local server")
      return
    }
    defer { server.stop() }

    let completeX = expectation(description: "typed problem - complete")

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let requestFactory = NetworkRequestFactory(baseURL: baseURL, mediaTypeDecoders: MediaTypeDecoders.Builder().build())
    defer { requestFactory.close() }

    let requestCancel =
      requestFactory.result(
        method: .get,
        pathTemplate: "problem",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: [.json],
        acceptTypes: [.json],
        headers: nil
      )
      .sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
            XCTAssertTrue(type(of: error) == SundayError.self, "Error is not a SundayError")
          }
          else {
            XCTFail("Request should have thrown problem")
          }
          completeX.fulfill()
        },
        receiveValue: { _ in }
      )

    waitForExpectations(timeout: 5.0) { _ in
      requestCancel.cancel()
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

    eventSource.addEventListener("test") { _, _, _ in
      eventSource.close()
      completeX.fulfill()
    }

    eventSource.connect()

    waitForExpectations(timeout: 5.0) { _ in
      eventSource.close()
    }
  }

  func testEventStreamBuilding() throws {

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

    let baseURL = URI.Template(format: serverURL.absoluteString)

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let eventPublisher = requestFactory.eventStream(
      method: .get,
      pathTemplate: "/events",
      pathParameters: nil,
      queryParameters: nil,
      body: Empty.none,
      contentTypes: [.json],
      acceptTypes: [.json],
      headers: nil,
      eventTypes: [
        "test": .erase(TestEvent.self),
      ]
    ) as RequestEventPublisher<TestEvent>

    let completeX = expectation(description: "complete received")

    var cancels: Set<AnyCancellable> = []

    eventPublisher.sink(
      receiveCompletion: { _ in

        XCTFail("unexpected complete")

        completeX.fulfill()
      },
      receiveValue: { event in

        cancels.forEach { $0.cancel() }

        completeX.fulfill()
        XCTAssertEqual(event.some, "test data")
      }
    ).store(in: &cancels)

    waitForExpectations(timeout: 2.0, handler: nil)
  }

  func testFluent() {

    let factory = NetworkRequestFactory(baseURL: "http://example.com", sessionConfiguration: .default)

    let restConfig = URLSessionConfiguration.rest()
    let restFactory = factory.with(sessionConfiguration: restConfig)

    XCTAssertEqual(restFactory.session.session.configuration, restConfig)
  }

  func testFluent2() {

    let factory = NetworkRequestFactory(baseURL: "http://example.com", sessionConfiguration: .default)

    let restSession = NetworkSession(configuration: .rest())
    let restFactory = factory.with(session: restSession)

    XCTAssertEqual(restFactory.session.session.configuration, restSession.session.configuration)
  }

}
