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

    struct SpecialParam: LosslessStringConvertible, URI.Template.ParameterValue {

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

    struct SpecialType: URI.Template.ParameterValue {}

    let template = URI.Template(format: "http://example.com/{id}")

    XCTAssertEqual(template.format, "http://example.com/{id}")

    try await XCTAssertThrowsError(try template.complete(parameters: ["id": SpecialType()])) { error in

      guard case URI.Template.Error.unsupportedParameterType(name: let paramName, type: _) = error else {
        return XCTFail("unexpected error")
      }

      XCTAssertEqual(paramName, "id")
    }
  }

  func testFailsWithUnsupportedHTTPParameterValue() async throws {

    struct SpecialType: Sendable {}

    try await XCTAssertThrowsError(try URI.Template.parameters(from: ["id": SpecialType()])) { error in

      guard case URI.Template.Error.unsupportedParameterType(name: let paramName, type: _) = error else {
        return XCTFail("unexpected error")
      }

      XCTAssertEqual(paramName, "id")
    }
  }

  func testFailsWithUnsupportedNestedHTTPParameterValue() async throws {

    struct SpecialType: Sendable {}

    try await XCTAssertThrowsError(try URI.Template.parameters(from: ["id": ["value": SpecialType()]])) { error in

      guard case URI.Template.Error.unsupportedParameterType(name: let paramName, type: _) = error else {
        return XCTFail("unexpected error")
      }

      XCTAssertEqual(paramName, "id")
    }
  }

  func testMissingAndNullVariablesExpandToNothing() throws {
    let expressions = ["{id}", "{+id}", "{#id}", "{.id}", "{/id}", "{;id}", "{?id}", "{&id}", "{id:3}", "{/id*}"]
    for expression in expressions {
      let template = URI.Template(format: "https://example.com/items\(expression)")
      XCTAssertEqual(try template.complete().absoluteString, "https://example.com/items", expression)
      let nullURL = try template.complete(parameters: ["id": nil])
      XCTAssertEqual(nullURL.absoluteString, "https://example.com/items", expression)
    }
  }

  func testUndefinedVariablesDoNotAddSeparators() throws {
    let cases = [
      ("{missing,first,nil,last,missing}", "one,two"),
      ("{+missing,first,nil,last,missing}", "one,two"),
      ("{#missing,first,nil,last,missing}", "#one,two"),
      ("{.missing,first,nil,last,missing}", ".one.two"),
      ("{/missing,first,nil,last,missing}", "/one/two"),
      ("{;missing,first,nil,last,missing}", ";first=one;last=two"),
      ("{?missing,first,nil,last,missing}", "?first=one&last=two"),
      ("{&missing,first,nil,last,missing}", "&first=one&last=two"),
    ]
    for (expression, suffix) in cases {
      let template = URI.Template(format: "https://example.com/items\(expression)")
      let url = try template.complete(parameters: ["first": "one", "nil": nil, "last": "two"])
      XCTAssertEqual(url.absoluteString, "https://example.com/items\(suffix)", expression)
    }
  }

  func testEmptyStringsRemainDefined() throws {
    let cases = [
      ("{id}", ""),
      ("{+id}", ""),
      ("{#id}", "#"),
      ("{.id}", "."),
      ("{/id}", "/"),
      ("{;id}", ";id"),
      ("{?id}", "?id="),
      ("{&id}", "&id="),
    ]
    for (expression, suffix) in cases {
      let template = URI.Template(format: "https://example.com/items\(expression)", parameters: ["id": ""])
      XCTAssertEqual(try template.complete().absoluteString, "https://example.com/items\(suffix)", expression)
    }
  }

  func testUndefinedVariablesPreserveLiteralSlashes() throws {
    let template = URI.Template(format: "https://example.com/items/{id}")
    XCTAssertEqual(try template.complete().absoluteString, "https://example.com/items/")
  }

  func testNullOverridesTemplateValuesInBaseAndRelativePaths() throws {
    let template = URI.Template(format: "https://example.com{/version}", parameters: ["version": "v1", "id": "123"])
    XCTAssertEqual(try template.complete(relative: "/items{/id}").absoluteString, "https://example.com/v1/items/123")
    let url = try template.complete(relative: "/items{/id}", parameters: ["version": nil, "id": nil])
    XCTAssertEqual(url.absoluteString, "https://example.com/items")
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
