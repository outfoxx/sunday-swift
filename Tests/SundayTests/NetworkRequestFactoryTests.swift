//
//  NetworkRequestFactoryTests.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import PotentCodables
@testable import Sunday
@testable import SundayServer
import XCTest


class NetworkRequestFactoryTests: XCTestCase {
  
  class TestProblem : Problem {
    
    static let type = URL(string: "http://example.com/test")!
    static let statusCode = HTTP.StatusCode.badRequest
    
    let extra: String
    
    init(extra: String, instance: URL? = nil) {
      self.extra = extra
      super.init(type: Self.type,
                 title: "Test Problem",
                 statusCode: Self.statusCode,
                 detail: "A Test Problem",
                 instance: instance,
                 parameters: nil)
    }
    
    required init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: AnyCodingKey.self)
      self.extra = try container.decode(String.self, forKey: AnyCodingKey("extra"))
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
          GET { req, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(statusCode: TestProblem.statusCode, headers: headers, value: testProblem)
          }
        }
      }
    }
    
    let url = server.start()
    XCTAssertNotNil(url)
    
    let completeX = expectation(description: "typed problem - complete")
    
    let baseURL = URI.Template(template: url!.absoluteString)
    
    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }
    
    requestFactory.registerProblem(type: TestProblem.type, problemType: TestProblem.self)
    
    let requestCancel =
      requestFactory.result(method: .get, pathTemplate: "problem",
                            pathParameters: nil, queryParameters: nil, body: Empty.none,
                            contentTypes: [.json], acceptTypes: [.json], headers: nil)
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
          GET { req, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(statusCode: TestProblem.statusCode, headers: headers, value: testProblem)
          }
        }
      }
    }
    
    let url = server.start()
    XCTAssertNotNil(url)
    
    let completeX = expectation(description: "typed problem - complete")
    
    let baseURL = URI.Template(template: url!.absoluteString)
    
    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }
    
    let requestCancel =
      requestFactory.result(method: .get, pathTemplate: "problem",
                            pathParameters: nil, queryParameters: nil, body: Empty.none,
                            contentTypes: [.json], acceptTypes: [.json], headers: nil)
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
          GET { req, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.html.value]]
            res.send(status: .badRequest, headers: headers, value: "<error>Error</error>")
          }
        }
      }
    }
    
    let url = server.start()
    XCTAssertNotNil(url)
    
    let completeX = expectation(description: "typed problem - complete")
    
    let baseURL = URI.Template(template: url!.absoluteString)
    
    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }
    
    let requestCancel =
      requestFactory.result(method: .get, pathTemplate: "problem",
                            pathParameters: nil, queryParameters: nil, body: Empty.none,
                            contentTypes: [.json], acceptTypes: [.json], headers: nil)
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
          GET { req, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(status: .badRequest, headers: headers, body: Data())
          }
        }
      }
    }
    
    let url = server.start()
    XCTAssertNotNil(url)
    
    let completeX = expectation(description: "typed problem - complete")
    
    let baseURL = URI.Template(template: url!.absoluteString)
    
    let requestFactory = NetworkRequestFactory(baseURL: baseURL)
    defer { requestFactory.close() }
    
    let requestCancel =
      requestFactory.result(method: .get, pathTemplate: "problem",
                            pathParameters: nil, queryParameters: nil, body: Empty.none,
                            contentTypes: [.json], acceptTypes: [.json], headers: nil)
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
          GET { req, res in
            let headers = [HTTP.StdHeaders.contentType: [MediaType.problem.value]]
            res.send(statusCode: TestProblem.statusCode, headers: headers, value: TestProblem(extra: "none"))
          }
        }
      }
    }
    
    let url = server.start()
    XCTAssertNotNil(url)
    
    let completeX = expectation(description: "typed problem - complete")
    
    let baseURL = URI.Template(template: url!.absoluteString)
    
    let requestFactory = NetworkRequestFactory(baseURL: baseURL, mediaTypeDecoders: MediaTypeDecoders.Builder().build())
    defer { requestFactory.close() }
    
    let requestCancel =
      requestFactory.result(method: .get, pathTemplate: "problem",
                            pathParameters: nil, queryParameters: nil, body: Empty.none,
                            contentTypes: [.json], acceptTypes: [.json], headers: nil)
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

}
