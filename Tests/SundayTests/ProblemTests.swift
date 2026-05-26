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
import PotentCodables
import PotentJSON
import Sunday
import XCTest


class ProblemTests: XCTestCase {

  struct TestProblem: Problem {

    static let typeURL = URL(string: "http://example.com/test")!

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
      self.status = 200
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

    var description: String { "CustomDesc" }

  }

  func testInitFromStatus() throws {

    let problem1 = HTTP.StatusProblem(statusCode: 404)
    XCTAssertEqual(problem1.type, URL(string: "about:blank"))
    XCTAssertEqual(problem1.status, 404)
    XCTAssertEqual(problem1.statusCode, .notFound)
    XCTAssertEqual(problem1.title, HTTP.statusText[.notFound])
    XCTAssertNil(problem1.detail)
    XCTAssertNil(problem1.instance)
    XCTAssertNil(problem1.parameters)

    let problem2 = HTTP.StatusProblem(statusCode: .notFound)
    XCTAssertEqual(problem2.type, URL(string: "about:blank"))
    XCTAssertEqual(problem2.status, 404)
    XCTAssertEqual(problem2.statusCode, .notFound)
    XCTAssertEqual(problem2.title, HTTP.statusText[.notFound])
    XCTAssertNil(problem2.detail)
    XCTAssertNil(problem2.instance)
    XCTAssertNil(problem2.parameters)

  }

  func testEncodingOmitsAbsentOptionalMembers() throws {

    let problemJSON = try JSON.Encoder.default.encodeString(HTTP.StatusProblem(statusCode: 404))

    XCTAssertFalse(problemJSON.contains("\"detail\""))
    XCTAssertFalse(problemJSON.contains("\"instance\""))

  }

  func testInitFromTree() throws {

    let problem1 =
      GenericProblem(statusCode: 400, data: [
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

    let problem2 = GenericProblem(statusCode: .badRequest, data: [
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
      GenericProblem(
        type: TestProblem.typeURL,
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

    let decodedProblem = try JSON.Decoder.default.decode(GenericProblem.self, from: problemJSON)

    XCTAssertEqual(problem.type, decodedProblem.type)
    XCTAssertEqual(problem.title, decodedProblem.title)
    XCTAssertEqual(problem.status, decodedProblem.status)
    XCTAssertEqual(problem.detail, decodedProblem.detail)
    XCTAssertEqual(problem.instance, decodedProblem.instance)
    XCTAssertEqual(["extra": AnyValue.string(problem.extra)], decodedProblem.parameters)
  }

  func testStatusProblemCodableFlattensParameters() throws {

    let problem =
      HTTP.StatusProblem(
        type: TestProblem.typeURL,
        title: "Test Problem",
        status: 200,
        detail: "A Test Problem",
        instance: URL(string: "id:12345"),
        parameters: ["extra": "some extra"]
      )

    let problemJSON = try JSON.Encoder.default.encodeString(problem)

    XCTAssertTrue(problemJSON.contains("\"extra\""))
    XCTAssertFalse(problemJSON.contains("\"parameters\""))

    let decodedProblem = try JSON.Decoder.default.decode(HTTP.StatusProblem.self, from: problemJSON)

    XCTAssertEqual(problem.type, decodedProblem.type)
    XCTAssertEqual(problem.title, decodedProblem.title)
    XCTAssertEqual(problem.status, decodedProblem.status)
    XCTAssertEqual(problem.detail, decodedProblem.detail)
    XCTAssertEqual(problem.instance, decodedProblem.instance)
    XCTAssertEqual(problem.parameters, decodedProblem.parameters)
  }

  func testCustomDecodingForGenericProblems() throws {

    let customProblem = TestProblem(extra: "Some Extra", instance: URL(string: "id:12345"))
    let genericProblem =
      GenericProblem(
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

  func testDecodingFailsWhenProblemMissingType() throws {

    let problemJSON =
      """
      {
        "title": "Bad Request",
        "status": 400
      }
      """

    XCTAssertThrowsError(try JSON.Decoder.default.decode(GenericProblem.self, from: problemJSON)) { error in
      guard case DecodingError.dataCorrupted(let errorCtx) = error else {
        return XCTFail("Wrong Error")
      }
      XCTAssertEqual(errorCtx.debugDescription, "Required Value Missing")
    }
  }

  func testDecodingFailsWhenProblemMissingTitle() throws {

    let problemJSON =
      """
      {
        "type": "http://example.com/docs/bad-request",
        "status": 400
      }
      """

    XCTAssertThrowsError(try JSON.Decoder.default.decode(GenericProblem.self, from: problemJSON)) { error in
      guard case DecodingError.dataCorrupted(let errorCtx) = error else {
        return XCTFail("Wrong Error")
      }
      XCTAssertEqual(errorCtx.debugDescription, "Required Value Missing")
    }
  }

  func testDecodingFailsWhenProblemMissingStatus() throws {

    let problemJSON =
      """
      {
        "type": "http://example.com/docs/bad-request",
        "title": "Bad Request"
      }
      """

    XCTAssertThrowsError(try JSON.Decoder.default.decode(GenericProblem.self, from: problemJSON)) { error in
      guard case DecodingError.dataCorrupted(let errorCtx) = error else {
        return XCTFail("Wrong Error")
      }
      XCTAssertEqual(errorCtx.debugDescription, "Required Value Missing")
    }
  }

}
