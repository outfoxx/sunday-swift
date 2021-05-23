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

import PotentJSON
@testable import Sunday
import XCTest

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

  func testEquqlity() {

    let mediaType = MediaType.html.with("utf-8", forParameter: .charSet)
    XCTAssertEqual(mediaType, mediaType)

    XCTAssertEqual(
      MediaType.html.with("utf-8", forParameter: .charSet).with("123", forParameter: "test"),
      MediaType.html.with("utf-8", forParameter: .charSet).with("123", forParameter: "test")
    )

    XCTAssertNotEqual(
      MediaType("application/text"),
      MediaType("text/json")
    )

    XCTAssertNotEqual(
      MediaType("application/x-html"),
      MediaType("application/x.html")
    )

    XCTAssertNotEqual(
      MediaType("text/html"),
      MediaType("text/json")
    )

    XCTAssertNotEqual(
      MediaType("application/problem+json"),
      MediaType("application/problem+cbor")
    )

    XCTAssertNotEqual(
      MediaType.html.with("123", forParameter: "a").with("123", forParameter: "b"),
      MediaType.html.with("123", forParameter: "a").with("456", forParameter: "b")
    )

  }

  func testParmeterAccess() {

    let mediaType = MediaType.html.with("123", forParameter: "a").with("456", forParameter: "b")

    XCTAssertEqual(mediaType.parameter("a"), "123")
    XCTAssertEqual(mediaType.parameter("b"), "456")
    XCTAssertNil(mediaType.parameter("c"))
  }

  func testParmeterOverwrite() {

    let base = MediaType.html

    XCTAssertEqual(
      base.with("123", forParameter: "a").with("456", forParameter: "a").parameter("a"),
      "456"
    )
    XCTAssertEqual(
      base.with("456", forParameter: "a").with("123", forParameter: "a").parameter("a"),
      "123"
    )
  }

  func testCompatibility() {

    XCTAssert(
      MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~=
        MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]),
      "Test compatibility"
    )

    XCTAssert(
      !(
        MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~=
          MediaType(type: .image, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"])
      ),
      "Test incompatibility in types"
    )

    XCTAssert(
      !(
        MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~=
          MediaType(type: .text, tree: .personal, subtype: "plain", suffix: .json, parameters: ["a": "b"])
      ),
      "Test incompatibility in trees"
    )

    XCTAssert(
      !(
        MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~=
          MediaType(type: .text, tree: .vendor, subtype: "html", suffix: .json, parameters: ["a": "b"])
      ),
      "Test incompatibility in subtypes"
    )

    XCTAssert(
      !(
        MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~=
          MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .xml, parameters: ["a": "b"])
      ),
      "Test incompatibility in suffixes"
    )

    XCTAssert(
      !(
        MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~=
          MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "c"])
      ),
      "Test incompatibility in parmeter values"
    )

    XCTAssert(
      !(
        MediaType(type: .text, tree: .vendor, subtype: "plain", suffix: .json, parameters: ["a": "b"]) ~=
          MediaType(type: .text, tree: .vendor, subtype: "plain", parameters: ["a": "c"])
      ),
      "Test incompatibility in parmeter values missing suffix"
    )

    XCTAssert(
      MediaType(type: .text, subtype: "html", parameters: ["custom-charset": "utf-16"]) ~=
        MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-8"]),
      "Test compatibility with different parameters"
    )

    XCTAssert(
      MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-8"]) ~=
        MediaType(type: .text, subtype: "html", parameters: ["test": "it"]),
      "Test compatibility with different parameters"
    )

    XCTAssert(
      MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-8"]) ~=
        MediaType(type: .text, subtype: "html", parameters: ["CHARSET": "UTF-8"]),
      "Test compatibility with different parameter cases"
    )

    XCTAssert(
      !(
        MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-8"]) ~=
          MediaType(type: .text, subtype: "html", parameters: ["charset": "utf-16"])
      ),
      "Test compatibility with different parameter values"
    )

    XCTAssert(
      MediaType(type: .text, subtype: "html") ~= MediaType(type: .any, subtype: "*"),
      "Test compatibility with wildcard type & subtype"
    )

    XCTAssert(
      MediaType(type: .text, subtype: "html") ~= MediaType(type: .any, subtype: "html"),
      "Test compatibility with wildcard type"
    )

    XCTAssert(
      MediaType(type: .text, subtype: "html") ~= MediaType(type: .text, subtype: "*"),
      "Test compatibility with wildcard subtype"
    )

    switch "*/*" {
    case MediaType.anyImage:
      break
    default:
      fatalError("Pattern match failed")
    }
  }

  func testParse() {
    XCTAssertEqual(
      MediaType(
        type: .application,
        tree: .standard,
        subtype: "problem",
        suffix: .json,
        parameters: ["charset": "utf-8"]
      ),
      MediaType("application/problem+json;charset=utf-8"),
      "Test parsing"
    )
    XCTAssertEqual(
      MediaType(type: .application, tree: .obsolete, subtype: "www-form-urlencoded"),
      MediaType("application/x-www-form-urlencoded"),
      "Test parsing with non-standard tree"
    )
    XCTAssertEqual(
      MediaType(type: .application, tree: .obsolete, subtype: "x509-ca-cert"),
      MediaType("application/x-x509-ca-cert"),
      "Test parsing with non-standard tree and complexs subtype"
    )
    XCTAssertEqual(
      MediaType(
        type: .application,
        tree: .vendor,
        subtype: "yaml",
        parameters: ["charset": "utf-8", "something": "else"]
      ),
      MediaType("application/vnd.yaml;charset=utf-8;something=else"),
      "Test parsing with multiple parameters"
    )
    XCTAssertEqual(
      MediaType(
        type: .application,
        tree: .vendor,
        subtype: "yaml",
        parameters: ["charset": "utf-8", "something": "else"]
      ),
      MediaType("APPLICATION/VND.YAML;CHARSET=UTF-8;SOMETHING=ELSE"),
      "Test parsing with different cases"
    )
    XCTAssertEqual(
      MediaType(
        type: .application,
        tree: .vendor,
        subtype: "yaml",
        parameters: ["charset": "utf-8", "something": "else"]
      ),
      MediaType("APPLICATION/VND.YAML  ;  CHARSET=UTF-8 ; SOMETHING=ELSE   "),
      "Test parsing with different random spacing"
    )

    XCTAssertEqual(MediaType("application/*")?.type, .application)
    XCTAssertEqual(MediaType("audio/*")?.type, .audio)
    XCTAssertEqual(MediaType("example/*")?.type, .example)
    XCTAssertEqual(MediaType("font/*")?.type, .font)
    XCTAssertEqual(MediaType("image/*")?.type, .image)
    XCTAssertEqual(MediaType("message/*")?.type, .message)
    XCTAssertEqual(MediaType("model/*")?.type, .model)
    XCTAssertEqual(MediaType("multipart/*")?.type, .multipart)
    XCTAssertEqual(MediaType("text/*")?.type, .text)
    XCTAssertEqual(MediaType("video/*")?.type, .video)
    XCTAssertEqual(MediaType("*/*")?.type, .any)

    XCTAssertEqual(MediaType("application/test")?.tree, .standard)
    XCTAssertEqual(MediaType("application/vnd.test")?.tree, .vendor)
    XCTAssertEqual(MediaType("application/prs.test")?.tree, .personal)
    XCTAssertEqual(MediaType("application/x.test")?.tree, .unregistered)
    XCTAssertEqual(MediaType("application/x-test")?.tree, .obsolete)

    XCTAssertEqual(MediaType("application/text+xml")?.suffix, .xml)
    XCTAssertEqual(MediaType("application/text+json")?.suffix, .json)
    XCTAssertEqual(MediaType("application/text+ber")?.suffix, .ber)
    XCTAssertEqual(MediaType("application/text+der")?.suffix, .der)
    XCTAssertEqual(MediaType("application/text+fastinfoset")?.suffix, .fastinfoset)
    XCTAssertEqual(MediaType("application/text+wbxml")?.suffix, .wbxml)
    XCTAssertEqual(MediaType("application/text+zip")?.suffix, .zip)
    XCTAssertEqual(MediaType("application/text+cbor")?.suffix, .cbor)
  }

  func testValue() {
    XCTAssertEqual(
      MediaType(
        type: .application,
        tree: .vendor,
        subtype: "yaml",
        parameters: ["charset": "utf-8", "something": "else"]
      ).value,
      "application/vnd.yaml;charset=utf-8;something=else"
    )
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
