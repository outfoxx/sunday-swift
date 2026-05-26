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
import Sunday
import SundayServer
import XCTest


class GeneratedAPITests: XCTestCase {

  struct TestResult: Codable, Equatable, Sendable {
    var message: String
    var count: Int
  }

  class API<TransportType: Transport> {

    let transport: TransportType

    init(transport: TransportType) {
      self.transport = transport
    }

    func testResult() async throws -> TestResult {
      return try await transport.result(
        method: .get,
        pathTemplate: "/test",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: nil,
        acceptTypes: [.json],
        headers: nil
      )
    }

    func testOperationResponse() async throws -> OperationResponse<TestResult> {
      return try await transport.response(
        method: .get,
        pathTemplate: "/test",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: nil,
        acceptTypes: [.json],
        headers: nil
      )
    }

    func testVoidOperationResponse() async throws -> OperationResponse<Void> {
      return try await transport.response(
        method: .get,
        pathTemplate: "/test",
        pathParameters: nil,
        queryParameters: nil,
        body: Empty.none,
        contentTypes: nil,
        acceptTypes: [.json],
        headers: nil
      )
    }

    func testOperation() -> Sunday.Operation<Empty, TestResult, TransportType> {
      return Sunday.Operation(
        transport: transport,
        spec: OperationSpec(
          method: .get,
          pathTemplate: "/test",
          body: Empty.none,
          acceptTypes: [.json]
        )
      )
    }

    func testVoidOperation() -> Sunday.Operation<Empty, Void, TransportType> {
      return Sunday.Operation(
        transport: transport,
        spec: OperationSpec(
          method: .get,
          pathTemplate: "/test",
          body: Empty.none,
          acceptTypes: [.json]
        )
      )
    }

    func testNilableOperation() -> Sunday.NilableOperation<Empty, TestResult, TransportType> {
      return Sunday.NilableOperation(
        transport: transport,
        spec: OperationSpec(
          method: .get,
          pathTemplate: "/test",
          body: Empty.none,
          acceptTypes: [.json]
        ),
        nilify: NilifySpec(statuses: [404])
      )
    }

    func testVoidNilableOperation() -> Sunday.NilableOperation<Empty, Void, TransportType> {
      return Sunday.NilableOperation(
        transport: transport,
        spec: OperationSpec(
          method: .get,
          pathTemplate: "/test",
          body: Empty.none,
          acceptTypes: [.json]
        ),
        nilify: NilifySpec(statuses: [404])
      )
    }

  }

  func testNilableOperationExposesGeneratedSpec() {

    let transport = URLSessionTransport(baseURL: "http://example.com")
    defer { transport.close() }

    let api = API(transport: transport)
    let operation = api.testNilableOperation()

    XCTAssertEqual(operation.spec.method, .get)
    XCTAssertEqual(operation.spec.pathTemplate, "/test")
    XCTAssertEqual(operation.spec.acceptTypes, [.json])
    XCTAssertEqual(operation.nilify.statuses, [404])
  }

  func testResultCall() async throws {

    let testResult = TestResult(message: "Test", count: 10)

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/test") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.json.value]]
            res.send(status: .ok, headers: headers, value: testResult)
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

    let api = API(transport: transport)

    let result = try await api.testResult()

    XCTAssertEqual(result, testResult)
  }

  func testOperationResponseCall() async throws {

    let testResult = TestResult(message: "Test", count: 10)

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/test") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.json.value]]
            res.send(status: .ok, headers: headers, value: testResult)
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

    let api = API(transport: transport)

    let response = try await api.testOperationResponse()

    XCTAssertEqual(response.result, testResult)
    XCTAssertEqual(response.contentType, .json)
    XCTAssertEqual(
      response.header(named: HTTP.StdHeaders.contentType),
      MediaType.json.value
    )
    XCTAssertEqual(response.headers(named: HTTP.StdHeaders.contentType), [MediaType.json.value])
  }

  func testVoidOperationResponseCall() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/test") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentLength: ["0"]]
            res.send(status: .noContent, headers: headers, body: Data())
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

    let api = API(transport: transport)

    let response = try await api.testVoidOperationResponse()

    XCTAssertEqual(response.header(named: HTTP.StdHeaders.contentLength), "0")
  }

  func testOperationExecuteCall() async throws {

    let testResult = TestResult(message: "Test", count: 10)

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/test") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.json.value]]
            res.send(status: .ok, headers: headers, value: testResult)
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

    let api = API(transport: transport)

    let result = try await api.testOperation().execute()

    XCTAssertEqual(result, testResult)
  }

  func testNilableOperationExecuteOrNilReturnsValue() async throws {

    let testResult = TestResult(message: "Test", count: 10)

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/test") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.json.value]]
            res.send(status: .ok, headers: headers, value: testResult)
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

    let api = API(transport: transport)

    let result = try await api.testNilableOperation().executeOrNil()

    XCTAssertEqual(result, testResult)
  }

  func testNilableOperationExecuteOrNilReturnsNilForMatchingStatus() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/test") {
        GET { _, res in
          res.send(status: .notFound)
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

    let api = API(transport: transport)

    let result = try await api.testNilableOperation().executeOrNil()

    XCTAssertNil(result)
  }

  func testNilableOperationResponseOrNilReturnsResponse() async throws {

    let testResult = TestResult(message: "Test", count: 10)

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/test") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.json.value]]
            res.send(status: .ok, headers: headers, value: testResult)
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

    let api = API(transport: transport)

    let response = try await api.testNilableOperation().responseOrNil()

    XCTAssertEqual(response?.result, testResult)
    XCTAssertEqual(response?.contentType, .json)
  }

  func testNilableOperationResponseOrNilReturnsNilForMatchingStatus() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/test") {
        GET { _, res in
          res.send(status: .notFound)
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

    let api = API(transport: transport)

    let response = try await api.testNilableOperation().responseOrNil()

    XCTAssertNil(response)
  }

  func testVoidNilableOperationResponseOrNilReturnsResponse() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/test") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentLength: ["0"]]
            res.send(status: .noContent, headers: headers, body: Data())
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

    let api = API(transport: transport)

    let response = try await api.testVoidNilableOperation().responseOrNil()

    XCTAssertEqual(response?.header(named: HTTP.StdHeaders.contentLength), "0")
  }

  func testOperationTransportRequestCall() async throws {

    let transport = URLSessionTransport(baseURL: URI.Template(format: "https://example.com"))
    defer { transport.close() }

    let api = API(transport: transport)

    let request = try await api.testOperation().transportRequest()

    XCTAssertEqual(request.url?.absoluteString, "https://example.com/test")
    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.accept), MediaType.json.value)
  }

  func testVoidOperationOperationResponseCall() async throws {

    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/test") {
          GET { _, res in
            let headers = [HTTP.StdHeaders.contentLength: ["0"]]
            res.send(status: .noContent, headers: headers, body: Data())
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

    let api = API(transport: transport)

    let response = try await api.testVoidOperation().response()

    XCTAssertEqual(response.header(named: HTTP.StdHeaders.contentLength), "0")
  }

}
