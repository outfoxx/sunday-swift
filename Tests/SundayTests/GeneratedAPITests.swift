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

  class API {

    struct TestResult: Codable, Equatable {
      var message: String
      var count: Int
    }

    let requestFactory: RequestFactory

    init(requestFactory: RequestFactory) {
      self.requestFactory = requestFactory
    }

    func testResult() async throws -> TestResult {
      return try await requestFactory.result(
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

    func testResultResponse() async throws -> ResultResponse<TestResult> {
      return try await requestFactory.resultResponse(
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

    func testVoidResultResponse() async throws -> ResultResponse<Void> {
      return try await requestFactory.resultResponse(
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

  }

  func testResultCall() async throws {

    let testResult = API.TestResult(message: "Test", count: 10)

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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let api = API(requestFactory: requestFactory)

    let result = try await api.testResult()

    XCTAssertEqual(result, testResult)
  }

  func testResultResponseCall() async throws {

    let testResult = API.TestResult(message: "Test", count: 10)

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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let api = API(requestFactory: requestFactory)

    let resultResponse = try await api.testResultResponse()

    XCTAssertEqual(resultResponse.result, testResult)
    XCTAssertEqual(
      resultResponse.response.value(forHTTPHeaderField: HTTP.StdHeaders.contentType),
      MediaType.json.value
    )
  }

  func testVoidResultResponseCall() async throws {

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

    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }

    let api = API(requestFactory: requestFactory)

    let resultResponse = try await api.testVoidResultResponse()

    XCTAssertEqual(resultResponse.response.value(forHTTPHeaderField: HTTP.StdHeaders.contentLength), "0")
  }

}
