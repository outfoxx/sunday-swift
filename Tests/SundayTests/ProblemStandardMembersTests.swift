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
        if reference.isEmpty {
          XCTAssertNil(value.typeURI)
          XCTAssertNil(value.instanceURI)
        }
        else {
          XCTAssertEqual(value.typeURI?.absoluteString, reference)
          XCTAssertEqual(value.instanceURI?.absoluteString, reference)
        }
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
      let encoder = Foundation.JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let baseline: [String: Any] = ["type": "urn:custom", "status": 409, "title": "", "detail": "",
                                      "instance": "", "extra": "required", "trace": NSNull(),
      ]
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
          XCTAssertEqual(try encoder.encode(actual), try encoder.encode(expected))
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
  func testNormalizedDecoderPreservesConfiguredExtensionsAndPresence() throws {
    let decoder = Foundation.JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    decoder.dataDecodingStrategy = .base64
    decoder.userInfo[.init(rawValue: "trace")!] = "configured"
    let input = Data((#"{"detail":42,"date":100,"data":"AQI=","nested":{"detail":42},"# +
      #""values":[1,2],"number":7,"flag":true}"#).utf8)
    let value = try decoder.decode(DecoderProbe.self, from: input)
    XCTAssertEqual(value.date, Date(timeIntervalSince1970: 100))
    XCTAssertEqual(value.data, Data([1, 2]))
    XCTAssertEqual(value.type, "about:blank")
    XCTAssertEqual(value.tree["type"], .string("about:blank"))
    XCTAssertNil(value.tree["detail"])
    XCTAssertEqual(value.tree["nested"]?["detail"], 42)
  }

  func testGenericTransportPreservesRawExtensionKeys() throws {
    let decoder = PotentJSON.JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let transport = URLSessionTransport(baseURL: "https://example.com",
      mediaTypeDecoders: MediaTypeDecoders.Builder().registerJSON(decoder: decoder).build())
    defer { transport.close() }
    let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404,
      httpVersion: nil, headerFields: ["Content-Type": "application/problem+json"])!
    let source = #"{"trace_id":"raw","traceId":"camel","nested":{"detail":42},"trace":null}"#
    let error = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: response,
      data: Data(source.utf8)))
    let problem = try XCTUnwrap(transport.parse(error: error) as? GenericProblem)
    XCTAssertEqual(problem.parameters?["trace_id"], .string("raw"))
    XCTAssertEqual(problem.parameters?["traceId"], .string("camel"))
    XCTAssertEqual(problem.parameters?["trace"], .nil)
    XCTAssertEqual(problem.parameters?["nested"]?["detail"], 42)
    struct KeyProbe: Decodable { let traceId: String }
    XCTAssertEqual(try decoder.decode(KeyProbe.self, from: #"{"trace_id":"still configured"}"#).traceId,
      "still configured")
    for status in ["401.5", "401.00000000000001"] {
      let invalid = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: response,
        data: Data("{\"type\":\"urn:custom\",\"status\":\(status)}".utf8)))
      XCTAssertTrue(transport.parse(error: invalid) is SundayError)
    }
  }

  private struct DecoderProbe: Decodable {
    let type: String
    let date: Date
    let data: Data
    let tree: AnyValue

    init(from decoder: Decoder) throws {
      let normalized = try ProblemDecoding.normalized(decoder)
      XCTAssertEqual(normalized.userInfo[.init(rawValue: "trace")!] as? String, "configured")
      XCTAssertTrue(normalized.codingPath.isEmpty)
      tree = try AnyValue(from: normalized)
      let container = try normalized.container(keyedBy: AnyCodingKey.self)
      XCTAssertEqual(Set(container.allKeys.map(\.stringValue)),
        Set(["type", "date", "data", "nested", "values", "number", "flag"]))
      XCTAssertFalse(container.contains("detail"))
      XCTAssertThrowsError(try container.decode(String.self, forKey: "detail"))
      XCTAssertThrowsError(try container.decodeNil(forKey: "detail"))
      XCTAssertFalse(try container.decodeNil(forKey: "type"))
      type = try container.decode(String.self, forKey: "type")
      date = try container.decode(Date.self, forKey: "date")
      data = try container.decode(Data.self, forKey: "data")
      XCTAssertTrue(try container.decode(Bool.self, forKey: "flag"))
      XCTAssertEqual(try container.decode(Double.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(Float.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(Int.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(Int8.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(Int16.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(Int32.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(Int64.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(UInt.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(UInt8.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(UInt16.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(UInt32.self, forKey: "number"), 7)
      XCTAssertEqual(try container.decode(UInt64.self, forKey: "number"), 7)
      let nested = try container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: "nested")
      XCTAssertEqual(try nested.decode(Int.self, forKey: "detail"), 42)
      var values = try container.nestedUnkeyedContainer(forKey: "values")
      XCTAssertEqual(try values.decode(Int.self), 1)
      XCTAssertEqual(try values.decode(Int.self), 2)
      XCTAssertTrue(values.isAtEnd)
      XCTAssertEqual(try AnyValue(from: container.superDecoder(forKey: "type")), .string("about:blank"))
      XCTAssertEqual(try AnyValue(from: container.superDecoder(forKey: "nested"))["detail"], 42)
      XCTAssertThrowsError(try normalized.unkeyedContainer())
      XCTAssertThrowsError(try normalized.singleValueContainer().decode(String.self))
    }
  }

}
