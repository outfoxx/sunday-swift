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
@testable import Sunday
import XCTest

final class ProblemStandardMembersTests: XCTestCase {
  func testWrongCategoriesEqualMissing() throws {
    for member in ["type", "title", "status", "detail", "instance"] {
      let values = member == "status" ? ["null", "true", "false", "\"401\"", "[]", "{\"nested\":[null]}"] :
        ["null", "true", "false", "42", "[]", "{\"nested\":[null]}"]
      for value in values {
        let source = "{\"\(member)\":\(value),\"trace\":null,\"nested\":{\"detail\":42}}"
        for problem in [
          try PotentJSON.JSONDecoder().decode(GenericProblem.self, from: source),
          try Foundation.JSONDecoder().decode(GenericProblem.self, from: Data(source.utf8)),
        ] {
          XCTAssertEqual(problem.type, "about:blank")
          XCTAssertNil(problem.title)
          XCTAssertNil(problem.status)
          XCTAssertNil(problem.detail)
          XCTAssertNil(problem.instance)
          let encoded = try PotentJSON.JSONSerialization.json(from: PotentJSON.JSONEncoder().encode(problem))
          XCTAssertEqual(encoded.type, .string("about:blank"))
          XCTAssertEqual(encoded.trace, .null)
          XCTAssertEqual(encoded.nested?.detail, 42)
          guard case .object(let fields) = encoded else { return XCTFail("Expected object") }
          XCTAssertEqual(Set(fields.keys), Set(["type", "trace", "nested"]))
        }
      }
    }
  }

  func testCorrectCategoriesStillValidate() throws {
    for source in ["{\"status\":401.5}", "{\"status\":999999999999999999999999}"] {
      XCTAssertThrowsError(try PotentJSON.JSONDecoder().decode(GenericProblem.self, from: source))
      XCTAssertThrowsError(try Foundation.JSONDecoder().decode(GenericProblem.self, from: Data(source.utf8)))
    }
    let problem = try PotentJSON.JSONDecoder().decode(GenericProblem.self,
      from: "{\"title\":\"\",\"detail\":\"\"}")
    XCTAssertEqual(problem.type, "about:blank")
    XCTAssertEqual(problem.title, "")
    XCTAssertEqual(problem.detail, "")
    XCTAssertNil(problem.instance)
    for reference in ["", "../related", "https://example.com/problem"] {
      let source = "{\"type\":\"\(reference)\",\"instance\":\"\(reference)\"}"
      for value in [
        try PotentJSON.JSONDecoder().decode(GenericProblem.self, from: source),
        try Foundation.JSONDecoder().decode(GenericProblem.self, from: Data(source.utf8)),
      ] {
        XCTAssertEqual(value.type, reference)
        XCTAssertEqual(value.instance, reference)
        XCTAssertEqual(value.typeURI, URL(string: reference))
        XCTAssertEqual(value.instanceURI, URL(string: reference))
        let encoded = try PotentJSON.JSONSerialization.json(from: PotentJSON.JSONEncoder().encode(value))
        XCTAssertEqual(encoded.type, .string(reference))
        XCTAssertEqual(encoded.instance, .string(reference))
      }
    }
  }

  func testTransportNormalizesBeforeRegisteredDispatch() throws {
    let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404,
      httpVersion: nil, headerFields: ["Content-Type": "application/problem+json"])!
    for registered in [false, true] {
      let transport = URLSessionTransport(baseURL: "https://example.com")
      defer { transport.close() }
      if registered {
        transport.registerProblem(type: "urn:custom", problemType: URLSessionTransportTests.TestProblem.self)
        transport.registerProblem(type: "", problemType: URLSessionTransportTests.TestProblem.self)
      }
      func decode(_ raw: [String: Any]) throws -> any Problem {
        let error = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: response,
          data: try JSONSerialization.data(withJSONObject: raw)))
        return try XCTUnwrap(transport.parse(error: error) as? any Problem)
      }
      let baseline: [String: Any] = ["type": "urn:custom", "status": 409, "title": "", "detail": "",
                                      "instance": "", "extra": "required", "trace": NSNull(),]
      for member in ["type", "title", "status", "detail", "instance"] {
        var missing = baseline
        missing.removeValue(forKey: member)
        let expected = try decode(missing)
        let wrong: [Any] = member == "status" ? [NSNull(), true, "401", [], [:]] : [NSNull(), true, 42, [], [:]]
        for value in wrong {
          var input = baseline
          input[member] = value
          let actual = try decode(input)
          XCTAssertEqual(String(describing: type(of: actual)), String(describing: type(of: expected)))
          XCTAssertEqual(try PotentJSON.JSONEncoder().encodeTree(actual),
                         try PotentJSON.JSONEncoder().encodeTree(expected))
        }
      }
      let empty = try decode(["type": "", "instance": "", "extra": "required"])
      XCTAssertEqual(empty.type, "")
      XCTAssertEqual(empty.instance, "")
      XCTAssertEqual(empty is URLSessionTransportTests.TestProblem, registered)
      XCTAssertEqual(empty.status, 404)
      XCTAssertNil(empty.title)
      XCTAssertEqual(try decode(baseline).status, 409)
      if registered {
        let invalid = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: response,
          data: Data(#"{"type":"urn:custom","extra":42}"#.utf8)))
        XCTAssertTrue(transport.parse(error: invalid) is SundayError)
      }
    }
  }

  func testContextDefaultsAndLosslessExtensions() throws {
    let original = "{\"detail\":42,\"status\":409,\"trace\":9007199254740993123456789,\"nested\":{\"detail\":null}}"
    let source = Data(original.utf8)
    let (normalized, type) = try ProblemDecoding.contextualJSON(source, status: 404)
    XCTAssertEqual(type, "about:blank")
    let tree = try PotentJSON.JSONSerialization.json(from: normalized)
    XCTAssertEqual(tree.status, 409)
    XCTAssertEqual(tree.title, "Conflict")
    XCTAssertEqual(tree.trace, try PotentJSON.JSONSerialization.json(from: "[9007199254740993123456789]")[0])
    XCTAssertEqual(tree.nested?.detail, .null)
    XCTAssertEqual(source, Data(original.utf8))
  }
}
