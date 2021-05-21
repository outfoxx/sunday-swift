//
//  URITemplatesTests.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

@testable import Sunday
import URITemplate
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
  
  func testSlashHandling() {
    
    let template = URI.Template("http://{env}.example.com/api/v{ver}/")
    
    XCTAssertEqual(template.format, "http://{env}.example.com/api/v{ver}/")
    
    XCTAssertEqual(
      try template.complete(relative: "/items", parameters: ["env": "stg", "ver": "1"]),
      URL(string: "http://stg.example.com/api/v1/items")
    )
    
    XCTAssertEqual(
      try template.complete(relative: "items", parameters: ["env": "stg", "ver": "1"]),
      URL(string: "http://stg.example.com/api/v1/items")
    )
    
    let template1 = URI.Template("http://{env}.example.com/api/v{ver}")

    XCTAssertEqual(template1.format, "http://{env}.example.com/api/v{ver}")

    XCTAssertEqual(
      try template1.complete(relative: "/items", parameters: ["env": "stg", "ver": "1"]),
      URL(string: "http://stg.example.com/api/v1/items")
    )

    XCTAssertEqual(
      try template1.complete(relative: "items", parameters: ["env": "stg", "ver": "1"]),
      URL(string: "http://stg.example.com/api/v1/items")
    )
  }
  
  func testCompleteParametersOverrideTemplate() {
    
    let template = URI.Template(format: "http://{env}.example.com/api/v{ver}/", parameters: ["ver": "1"])
    
    XCTAssertEqual(template.format, "http://{env}.example.com/api/v{ver}/")
    XCTAssertEqual(template.parameters.keys.first, "ver")
    
    XCTAssertEqual(
      try template.complete(relative: "/items", parameters: ["env": "stg", "ver": "2"]),
      URL(string: "http://stg.example.com/api/v2/items")
    )
  }
  
  func testCustomPathConvertibleAreSerializedCorrectly() {
    
    struct SpecialParam : CustomPathConvertible {
      
      var pathDescription: String {
        "special-param"
      }
      
    }
    
    let template = URI.Template(format: "http://example.com/{id}")
    
    XCTAssertEqual(template.format, "http://example.com/{id}")
    
    XCTAssertEqual(
      try template.complete(parameters: ["id": SpecialParam()]),
      URL(string: "http://example.com/special-param")
    )
  }
  
  func testCustomStringConvertibleAreSerializedCorrectly() {
    
    struct SpecialParam : CustomStringConvertible {
      
      var description: String {
        "special-string"
      }
      
    }
    
    let template = URI.Template(format: "http://example.com/{id}")
    
    XCTAssertEqual(template.format, "http://example.com/{id}")
    
    XCTAssertEqual(
      try template.complete(parameters: ["id": SpecialParam()]),
      URL(string: "http://example.com/special-string")
    )
  }
  
  func testVariableValuesConvertibleAreSerializedCorrectly() {
    
    let template = URI.Template(format: "http://example.com/{id}")
    
    XCTAssertEqual(template.format, "http://example.com/{id}")
    
    XCTAssertEqual(
      try template.complete(parameters: ["id": ["test": 1]]).absoluteString.removingPercentEncoding,
      "http://example.com/[\"test\": 1]"
    )
  }
  
  func testFailsWithUnsupportedValue() {
    
    class SpecialType {}
    
    let template = URI.Template(format: "http://example.com/{id}")
    
    XCTAssertEqual(template.format, "http://example.com/{id}")
    
    XCTAssertThrowsError(try template.complete(parameters: ["id": SpecialType()])) { error in
      
      guard case URI.Template.Error.unsupportedParameterType(name: let paramName, type: _) = error else {
        return XCTFail("unexpected error")
      }
      
      XCTAssertEqual(paramName, "id")
    }
  }
  
  func testFailsWithMissingParameter() {
    
    class SpecialType {}
    
    let template = URI.Template(format: "http://example.com/{id}")
    
    XCTAssertEqual(template.format, "http://example.com/{id}")
    
    XCTAssertThrowsError(try template.complete()) { error in
      
      guard case URI.Template.Error.missingParameterValue(name: let paramName) = error else {
        return XCTFail("unexpected error")
      }
      
      XCTAssertEqual(paramName, "id")
    }
  }

  func testMutiplePathVariable() {
    let pathTemplate = URI.Template(
      format: "http://example.com/v{reallyLongVariable}/devices/{deviceId}/messages/{messageId}/payloads",
      parameters: [
        "reallyLongVariable": 1,
        "deviceId": 123,
        "messageId": 456,
      ]
    )

    let encodedPath = try! pathTemplate.complete()

    XCTAssertEqual(encodedPath, URL(string: "http://example.com/v1/devices/123/messages/456/payloads"))
  }

}
