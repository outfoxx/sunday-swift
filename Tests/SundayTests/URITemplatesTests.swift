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

@testable import Sunday
import ScreamURITemplate
import XCTest


class URITemplatesTests: XCTestCase {

  func testInit() {

    let template = URI.Template("http://{env}.example.com/api/v{ver}")

    XCTAssertEqual(template.format, "http://{env}.example.com/api/v{ver}")
    XCTAssertEqual(template.parameters.isEmpty, true)
  }

  func testInitDropsTrailingSlash() {

    let template = URI.Template("http://{env}.example.com/api/v{ver}/")

    XCTAssertEqual(template.format, "http://{env}.example.com/api/v{ver}/")
    XCTAssertEqual(template.parameters.isEmpty, true)
  }

  func testLiteralInit() {

    let template: URI.Template = "http://{env}.example.com/api/v{ver}"

    XCTAssertEqual(template.format, "http://{env}.example.com/api/v{ver}")
    XCTAssertEqual(template.parameters.isEmpty, true)
  }

  func testSlashHandling() async throws {

    let template = URI.Template("http://{env}.example.com/api/v{ver}/")

    XCTAssertEqual(template.format, "http://{env}.example.com/api/v{ver}/")

    let url1 = try template.complete(relative: "/items", parameters: ["env": "stg", "ver": "1"])
    XCTAssertEqual(url1, URL(string: "http://stg.example.com/api/v1/items"))

    let url2 = try template.complete(relative: "items", parameters: ["env": "stg", "ver": "1"])
    XCTAssertEqual(url2, URL(string: "http://stg.example.com/api/v1/items"))

    let template1 = URI.Template("http://{env}.example.com/api/v{ver}")
    XCTAssertEqual(template1.format, "http://{env}.example.com/api/v{ver}")

    let url3 = try template1.complete(relative: "/items", parameters: ["env": "stg", "ver": "1"])
    XCTAssertEqual(url3, URL(string: "http://stg.example.com/api/v1/items"))

    let url4 = try template1.complete(relative: "items", parameters: ["env": "stg", "ver": "1"])
    XCTAssertEqual(url4, URL(string: "http://stg.example.com/api/v1/items"))
  }

  func testCompleteParametersOverrideTemplate() async throws {

    let template = URI.Template(format: "http://{env}.example.com/api/v{ver}/", parameters: ["ver": "1"])

    XCTAssertEqual(template.format, "http://{env}.example.com/api/v{ver}/")
    XCTAssertEqual(template.parameters.keys.first, "ver")

    let url = try template.complete(relative: "/items", parameters: ["env": "stg", "ver": "2"])
    XCTAssertEqual(url, URL(string: "http://stg.example.com/api/v2/items"))
  }

  func testCustomPathEncodersOverrideDefaultSerialization() async throws {

    let encoders: PathEncoders = .default.add(converter: { (_: UUID) in "custom-uuid" })

    let template = URI.Template(format: "http://example.com/{id}")

    XCTAssertEqual(template.format, "http://example.com/{id}")

    let url = try template.complete(parameters: ["id": UUID()], encoders: encoders)
    XCTAssertEqual(url, URL(string: "http://example.com/custom-uuid"))
  }

  func testCustomPathEncodableAreSerializedCorrectly() async throws {

    struct SpecialParam: PathEncodable {

      var pathDescription: String {
        "special-param"
      }

    }

    let template = URI.Template(format: "http://example.com/{id}")

    XCTAssertEqual(template.format, "http://example.com/{id}")

    let url = try template.complete(parameters: ["id": SpecialParam()])
    XCTAssertEqual(url, URL(string: "http://example.com/special-param"))
  }

  func testLosslessStringConvertibleAreSerializedCorrectly() async throws {

    struct SpecialParam: LosslessStringConvertible {

      let value: String

      init() {
        value = "special-string"
      }

      init?(_ description: String) {
        value = description
      }

      var description: String {
        value
      }

    }

    let template = URI.Template(format: "http://example.com/{id}")

    XCTAssertEqual(template.format, "http://example.com/{id}")

    let url = try template.complete(parameters: ["id": SpecialParam()])
    XCTAssertEqual(url, URL(string: "http://example.com/special-string"))
  }

  func testVariableValuesConvertibleAreSerializedCorrectly() async throws {

    let template = URI.Template(format: "http://example.com/{id}")

    XCTAssertEqual(template.format, "http://example.com/{id}")

    let url = try template.complete(parameters: ["id": ["test": "1"]]).absoluteString.removingPercentEncoding
    XCTAssertEqual(url, "http://example.com/test,1")
  }

  func testFailsWithUnsupportedValue() async throws {

    class SpecialType {}

    let template = URI.Template(format: "http://example.com/{id}")

    XCTAssertEqual(template.format, "http://example.com/{id}")

    try await XCTAssertThrowsError(try template.complete(parameters: ["id": SpecialType()])) { error in

      guard case URI.Template.Error.unsupportedParameterType(name: let paramName, type: _) = error else {
        return XCTFail("unexpected error")
      }

      XCTAssertEqual(paramName, "id")
    }
  }

  func testFailsWithMissingParameter() async throws {

    class SpecialType {}

    let template = URI.Template(format: "http://example.com/{id}")

    XCTAssertEqual(template.format, "http://example.com/{id}")

    try await XCTAssertThrowsError(try template.complete()) { error in

      guard case URI.Template.Error.missingParameterValue(name: let paramName) = error else {
        return XCTFail("unexpected error")
      }

      XCTAssertEqual(paramName, "id")
    }
  }

  func testMutiplePathVariable() async throws {
    let pathTemplate = URI.Template(
      format: "http://example.com/v{reallyLongVariable}/devices/{deviceId}/messages/{messageId}/payloads",
      parameters: [
        "reallyLongVariable": 1,
        "deviceId": 123,
        "messageId": 456,
      ]
    )

    let encodedPath = try? pathTemplate.complete()

    XCTAssertEqual(encodedPath, URL(string: "http://example.com/v1/devices/123/messages/456/payloads"))
  }

}
