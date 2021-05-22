//
//  ProblemTests.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCodables
import PotentJSON
import Sunday
import XCTest


class ProblemTests: XCTestCase {

  class TestProblem: Problem {

    static let type = URL(string: "http://example.com/test")!

    let extra: String

    init(extra: String, instance: URL? = nil) {
      self.extra = extra
      super.init(
        type: Self.type,
        title: "Test Problem",
        status: 200,
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

    override var description: String { "CustomDesc" }

  }

  func testInitFromStatus() throws {

    let problem1 = Problem(statusCode: 404)
    XCTAssertEqual(problem1.type, URL(string: "about:blank"))
    XCTAssertEqual(problem1.status, 404)
    XCTAssertEqual(problem1.statusCode, .notFound)
    XCTAssertEqual(problem1.title, HTTP.statusText[.notFound])
    XCTAssertNil(problem1.detail)
    XCTAssertNil(problem1.instance)
    XCTAssertNil(problem1.parameters)

    let problem2 = Problem(statusCode: .notFound)
    XCTAssertEqual(problem2.type, URL(string: "about:blank"))
    XCTAssertEqual(problem2.status, 404)
    XCTAssertEqual(problem2.statusCode, .notFound)
    XCTAssertEqual(problem2.title, HTTP.statusText[.notFound])
    XCTAssertNil(problem2.detail)
    XCTAssertNil(problem2.instance)
    XCTAssertNil(problem2.parameters)

  }

  func testInitFromTree() throws {

    let problem1 =
      Problem(statusCode: 400, data: [
        "type": "http://example.com/test",
        "title": "Test",
        "detail": "Some Details",
        "instance": "id:12345",
        "extra": "test",
      ])
    XCTAssertEqual(problem1.type, URL(string: "http://example.com/test"))
    XCTAssertEqual(problem1.status, 400)
    XCTAssertEqual(problem1.statusCode, .badRequest)
    XCTAssertEqual(problem1.title, "Test")
    XCTAssertEqual(problem1.detail, "Some Details")
    XCTAssertEqual(problem1.instance, URL(string: "id:12345"))
    XCTAssertEqual(problem1.parameters, ["extra": "test"])

    let problem2 = Problem(statusCode: .badRequest, data: [
      "type": "http://example.com/test",
      "title": "Test",
      "detail": "Some Details",
      "instance": "id:12345",
      "extra": "test",
    ])
    XCTAssertEqual(problem2.type, URL(string: "http://example.com/test"))
    XCTAssertEqual(problem2.status, 400)
    XCTAssertEqual(problem2.statusCode, .badRequest)
    XCTAssertEqual(problem2.title, "Test")
    XCTAssertEqual(problem2.detail, "Some Details")
    XCTAssertEqual(problem2.instance, URL(string: "id:12345"))
    XCTAssertEqual(problem2.parameters, ["extra": "test"])

  }

  func testDescription() {

    let problemDesc =
      Problem(
        type: TestProblem.type,
        title: "Test Problem",
        status: 200,
        detail: "A Test Problem",
        instance: URL(string: "id:12345"),
        parameters: ["extra": "some extra"]
      ).description


    XCTAssertTrue(problemDesc.contains("type="))
    XCTAssertTrue(problemDesc.contains("title="))
    XCTAssertTrue(problemDesc.contains("status="))
    XCTAssertTrue(problemDesc.contains("detail="))
    XCTAssertTrue(problemDesc.contains("instance="))
    XCTAssertTrue(problemDesc.contains("parameters="))
    XCTAssertTrue(problemDesc.contains("\"extra\":"))
  }

  func testCodableForCustomProblems() throws {

    let problem = TestProblem(extra: "Some Extra", instance: URL(string: "id:12345"))

    let problemJSON = try JSON.Encoder.default.encodeString(problem)

    let decodedProblem = try JSON.Decoder.default.decode(TestProblem.self, from: problemJSON)

    XCTAssertEqual(problem.type, decodedProblem.type)
    XCTAssertEqual(problem.title, decodedProblem.title)
    XCTAssertEqual(problem.status, decodedProblem.status)
    XCTAssertEqual(problem.detail, decodedProblem.detail)
    XCTAssertEqual(problem.instance, decodedProblem.instance)
    XCTAssertNil(decodedProblem.parameters)
    XCTAssertEqual(problem.extra, decodedProblem.extra)
  }

  func testGenericDecodingForCustomProblems() throws {

    let problem = TestProblem(extra: "Some Extra", instance: URL(string: "id:12345"))

    let problemJSON = try JSON.Encoder.default.encodeString(problem)

    let decodedProblem = try JSON.Decoder.default.decode(Problem.self, from: problemJSON)

    XCTAssertEqual(problem.type, decodedProblem.type)
    XCTAssertEqual(problem.title, decodedProblem.title)
    XCTAssertEqual(problem.status, decodedProblem.status)
    XCTAssertEqual(problem.detail, decodedProblem.detail)
    XCTAssertEqual(problem.instance, decodedProblem.instance)
    XCTAssertEqual(["extra": AnyValue.string(problem.extra)], decodedProblem.parameters)
  }

  func testCustomDecodingForGenericProblems() throws {

    let customProblem = TestProblem(extra: "Some Extra", instance: URL(string: "id:12345"))
    let genericProblem =
      Problem(
        type: customProblem.type,
        title: customProblem.title,
        status: customProblem.status,
        detail: customProblem.detail,
        instance: customProblem.instance,
        parameters: [
          "extra": AnyValue.string(customProblem.extra),
        ]
      )

    let problemJSON = try JSON.Encoder.default.encodeString(genericProblem)

    let decodedProblem = try JSON.Decoder.default.decode(TestProblem.self, from: problemJSON)

    XCTAssertEqual(customProblem.type, decodedProblem.type)
    XCTAssertEqual(customProblem.title, decodedProblem.title)
    XCTAssertEqual(customProblem.status, decodedProblem.status)
    XCTAssertEqual(customProblem.detail, decodedProblem.detail)
    XCTAssertEqual(customProblem.instance, decodedProblem.instance)
    XCTAssertNil(decodedProblem.parameters)
    XCTAssertEqual(customProblem.extra, decodedProblem.extra)
  }

}
