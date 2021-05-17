//
//  MediaTypeTests.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import PotentJSON
import XCTest
@testable import Sunday

class MediaTypeTests: XCTestCase {
  
  func testCodable() throws {
    
    let mediaType = MediaType.eventStream.with("utf-8", forParameter: .charSet)
    
    let encoded = try JSON.Encoder.default.encodeString(mediaType)
    let decoded = try JSON.Decoder.default.decode(MediaType.self, from: encoded)
    
    XCTAssertEqual(encoded, try JSONSerialization.string(from: JSON.string(mediaType.value)))
    XCTAssertEqual(decoded, mediaType)
  }
  
  func testParameterSupport() {
    
    let mediaType = MediaType.html.with("utf-8", forParameter: .charSet)
    
    XCTAssertEqual(mediaType.parameter(.charSet), "utf-8")
    XCTAssertEqual(mediaType.parameters, [MediaType.StandardParameterName.charSet.rawValue: "utf-8"])
  }
  
  func testPatternMatching() {
    
    let mediaType = MediaType.html.with("utf-8", forParameter: .charSet)
    
    XCTAssertTrue(mediaType ~= MediaType.html)
    XCTAssertFalse(mediaType ~= MediaType.anyImage)

    XCTAssertTrue("text/html" ~= MediaType.html)
    XCTAssertFalse("text/html" ~= MediaType.anyImage)

    XCTAssertTrue(mediaType ~= "text/html")
    XCTAssertFalse(mediaType ~= "image/*")
  }
  
  func testCompatibility() {

    XCTAssert(MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~= MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]),
              "Test compatibility")

    XCTAssert(!(MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~= MediaType(type: .image, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"])),
              "Test incompatibility in types")

    XCTAssert(!(MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~= MediaType(type: .text, tree: .personal, subtype: "plain", suffix: .json, parameters: ["a": "b"])),
              "Test incompatibility in trees")

    XCTAssert(!(MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~= MediaType(type: .text, tree: .vendor, subtype: "html", suffix: .json, parameters: ["a": "b"])),
              "Test incompatibility in subtypes")

    XCTAssert(!(MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~= MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .xml, parameters: ["a": "b"])),
              "Test incompatibility in suffixes")

    XCTAssert(!(MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~= MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "c"])),
              "Test incompatibility in parmeter values")

    XCTAssert(!(MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~= MediaType(type: .text, tree: .vendor, subtype: "plain", parameters: ["a": "c"])),
              "Test incompatibility in parmeter values missing suffix")

    XCTAssert(MediaType(type: .text, subtype: "html", parameters: ["custom-charset": "utf-16"]) ~= MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-8"]),
              "Test compatibility with different parameters")

    XCTAssert(MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-8"]) ~= MediaType(type: .text, subtype: "html", parameters: ["test": "it"]),
              "Test compatibility with different parameters")
    
    XCTAssert(MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-8"]) ~= MediaType(type: .text, subtype: "html", parameters: ["CHARSET": "UTF-8"]),
              "Test compatibility with different parameter cases")
    
    XCTAssert(!(MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-8"]) ~= MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-16"])),
              "Test compatibility with different parameter values")

    XCTAssert(MediaType(type: .text, subtype: "html") ~= MediaType(type: .any, subtype: "*"),
              "Test compatibility with wildcard type & subtype")

    XCTAssert(MediaType(type: .text, subtype: "html") ~= MediaType(type: .any, subtype: "html"),
              "Test compatibility with wildcard type")

    XCTAssert(MediaType(type: .text, subtype: "html") ~= MediaType(type: .text, subtype: "*"),
              "Test compatibility with wildcard subtype")

    switch "*/*" {
    case MediaType.anyImage:
      break
    default:
      fatalError("Pattern match failed")
    }
  }

  func testParse() {
    XCTAssertEqual(MediaType(type: .application, tree: .standard, subtype: "problem", suffix: .json, parameters: ["charset": "utf-8"]), MediaType("application/problem+json;charset=utf-8"),
                   "Test parsing")
    XCTAssertEqual(MediaType(type: .application, tree: .obsolete, subtype: "www-form-urlencoded"), MediaType("application/x-www-form-urlencoded"),
                   "Test parsing with non-standard tree")
    XCTAssertEqual(MediaType(type: .application, tree: .obsolete, subtype: "x509-ca-cert"), MediaType("application/x-x509-ca-cert"),
                   "Test parsing with non-standard tree and complexs subtype")
    XCTAssertEqual(MediaType(type: .application, tree: .vendor, subtype: "yaml", parameters: ["charset": "utf-8", "something": "else"]), MediaType("application/vnd.yaml;charset=utf-8;something=else"),
                   "Test parsing with multiple parameters")
    XCTAssertEqual(MediaType(type: .application, tree: .vendor, subtype: "yaml", parameters: ["charset": "utf-8", "something": "else"]), MediaType("APPLICATION/VND.YAML;CHARSET=UTF-8;SOMETHING=ELSE"),
                   "Test parsing with different cases")
    XCTAssertEqual(MediaType(type: .application, tree: .vendor, subtype: "yaml", parameters: ["charset": "utf-8", "something": "else"]), MediaType("APPLICATION/VND.YAML  ;  CHARSET=UTF-8 ; SOMETHING=ELSE   "),
                   "Test parsing with different random spacing")
  }

  func testValue() {
    XCTAssertEqual(MediaType(type: .application, tree: .vendor, subtype: "yaml", parameters: ["charset": "utf-8", "something": "else"]).value, "application/vnd.yaml;charset=utf-8;something=else")
  }

  func testSanity() {
    let json = MediaType.json.with(parameters: ["charset": "utf-8"])

    switch json {
    case .json, .jsonStructured:
      break
    case .html:
      XCTFail("Sanity check failed")
    default:
      XCTFail("Sanity check failed")
    }

    switch json {
    case .any:
      break
    case .html:
      XCTFail("Sanity check failed")
    default:
      XCTFail("Sanity check failed")
    }

    let html = MediaType.html.with(parameters: ["charset": "utf-8"])
    switch html {
    case .html:
      break
    case .json, .jsonStructured:
      XCTFail("Sanity check failed")
    default:
      XCTFail("Sanity check failed")
    }

  }
}
