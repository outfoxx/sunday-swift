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

import Sunday
import Foundation
import XCTest


public struct Security: Equatable, Codable, Sendable {

  var type: UpdateOp<String> = .unchanged
  var enc: PatchOp<Data> = .unchanged
  var sig: PatchOp<Data> = .unchanged

  public init(
    type: UpdateOp<String> = .unchanged,
    enc: PatchOp<Data> = .unchanged,
    sig: PatchOp<Data> = .unchanged
  ) {
    self.type = type
    self.enc = enc
    self.sig = sig
  }

  enum CodingKeys: CodingKey {
    case type
    case enc
    case sig
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.type = try container.decode(UpdateOp<String>.self, forKey: .type)
    self.enc = try container.decode(PatchOp<Data>.self, forKey: .enc)
    self.sig = try container.decode(PatchOp<Data>.self, forKey: .sig)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.type, forKey: .type)
    try container.encode(self.enc, forKey: .enc)
    try container.encode(self.sig, forKey: .sig)
  }
}

extension AnyPatchOp where Value == Security {

  static func merge(
    type: UpdateOp<String> = .unchanged,
    enc: PatchOp<Data> = .unchanged,
    sig: PatchOp<Data> = .unchanged
  ) -> Self {
    Self.merge(Security(type: type, enc: enc, sig: sig))
  }

}

public struct Device: Codable, Equatable {

  var name: UpdateOp<String> = .unchanged
  var security: UpdateOp<Security> = .unchanged
  var url: PatchOp<URL> = .unchanged
  var data: PatchOp<[String: String]> = .unchanged

  public init(
    name: UpdateOp<String> = .unchanged,
    security: UpdateOp<Security> = .unchanged,
    url: PatchOp<URL> = .unchanged,
    data: PatchOp<[String: String]> = .unchanged
  ) {
    self.name = name
    self.security = security
    self.url = url
    self.data = data
  }

  enum CodingKeys: CodingKey {
    case name
    case security
    case url
    case data
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.name = try container.decode(UpdateOp<String>.self, forKey: .name)
    self.security = try container.decode(UpdateOp<Security>.self, forKey: .security)
    self.url = try container.decode(PatchOp<URL>.self, forKey: .url)
    self.data = try container.decode(PatchOp<[String: String]>.self, forKey: .data)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.name, forKey: .name)
    try container.encode(self.security, forKey: .security)
    try container.encode(self.url, forKey: .url)
    try container.encode(self.data, forKey: .data)
  }
}



class PatchTests: XCTestCase {

  let encoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = .sortedKeys
    return enc
  }()


  let decoder: JSONDecoder = {
    let dec = JSONDecoder()
    return dec
  }()


  func testSimple() throws {

    let patch = Device(
      name: .set("Test"),
      security: .merge(
        type: .set("17"),
        enc: .set(Data([1, 2, 3])),
        sig: .delete
      ),
      data: .unchanged
    )

    let json = Data(#"{"name":"Test","security":{"enc":"AQID","sig":null,"type":"17"}}"#.utf8)

    XCTAssertEqual(try encoder.encode(patch), json)

    let decodedPatch = try decoder.decode(Device.self, from: json)
    XCTAssertEqual(decodedPatch, patch)


    let encodedJSON = try encoder.encode(decodedPatch)
    XCTAssertEqual(encodedJSON, json)
  }

  func testOmittedFieldsRemainUnchanged() throws {
    let patch = try decoder.decode(Device.self, from: Data("{}".utf8))
    XCTAssertEqual(patch.name, .unchanged)
    XCTAssertEqual(patch.security, .unchanged)
    XCTAssertEqual(patch.url, .unchanged)
    XCTAssertEqual(patch.data, .unchanged)
    XCTAssertEqual(try encoder.encode(patch), Data("{}".utf8))
  }

  func testDeletableFieldsPreserveExplicitDeletion() throws {
    let json = Data(#"{"data":null,"url":null}"#.utf8)
    let patch = try decoder.decode(Device.self, from: json)
    XCTAssertEqual(patch.url, .delete)
    XCTAssertEqual(patch.data, .delete)
    XCTAssertEqual(try encoder.encode(patch), json)
  }

  func testUpdateFieldsRejectNullWithCodingPath() throws {
    for (json, path) in [
      (#"{"name":null}"#, ["name"]),
      (#"{"security":null}"#, ["security"]),
      (#"{"security":{"type":null}}"#, ["security", "type"]),
    ] {
      XCTAssertThrowsError(try decoder.decode(Device.self, from: Data(json.utf8))) { error in
        guard case DecodingError.valueNotFound(_, let context) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(context.codingPath.map(\.stringValue), path)
      }
    }
  }

  func testMalformedPresentValuesAreNotTreatedAsOmitted() throws {
    for json in [#"{"name":12}"#, #"{"security":false}"#, #"{"security":{"enc":12}}"#] {
      XCTAssertThrowsError(try decoder.decode(Device.self, from: Data(json.utf8)))
    }
  }


  func testSynthesizedCodablePreservesStatesAndCancellation() throws {
    struct Fields: Codable, Equatable {
      var name: UpdateOp<String> = .unchanged
      var note: PatchOp<String> = .unchanged
    }
    var fields = try decoder.decode(Fields.self, from: Data("{}".utf8))
    XCTAssertEqual(fields, Fields())
    XCTAssertEqual(try encoder.encode(fields), Data("{}".utf8))
    fields.name = .set("changed")
    fields.note = .delete
    XCTAssertEqual(try encoder.encode(fields), Data(#"{"name":"changed","note":null}"#.utf8))
    fields.name = .unchanged
    XCTAssertEqual(try encoder.encode(fields), Data(#"{"note":null}"#.utf8))
    XCTAssertThrowsError(try decoder.decode(Fields.self, from: Data(#"{"name":null}"#.utf8)))
  }

  func testHelpersSkipUnchangedAndPreserveDeletion() {
    let update = UpdateOp<String>.unchanged
    let patch = PatchOp<String>.unchanged
    update.use { _ in XCTFail("Unchanged update invoked callback") }
    patch.use { _ in XCTFail("Unchanged patch invoked callback") }
    XCTAssertNil(update.get())
    func unexpectedDeletion() -> String { XCTFail("Unchanged invoked deletion fallback"); return "" }
    XCTAssertNil(patch.get(deleted: unexpectedDeletion()))
    XCTAssertEqual(UpdateOp.set("set").get(), "set")
    XCTAssertEqual(PatchOp<String>.delete.get(deleted: "deleted"), "deleted")
    PatchOp<String>.delete.use { XCTAssertNil($0) }
    UpdateOp.set("set").use { XCTAssertEqual($0, "set") }
    PatchOp.set("set").use { XCTAssertEqual($0, "set") }
    XCTAssertTrue(update.isUnchanged)
    XCTAssertTrue(patch.isUnchanged)
    XCTAssertFalse(PatchOp<String>.delete.isUnchanged)
    XCTAssertFalse(UpdateOp.set("set").isUnchanged)
    XCTAssertEqual(String(describing: update), "unchanged")
    XCTAssertEqual(String(describing: patch), "unchanged")
  }

  func testStandaloneUnchangedAndNullSetsHaveNoWireRepresentation() throws {
    XCTAssertThrowsError(try encoder.encode(UpdateOp<String>.unchanged))
    XCTAssertThrowsError(try encoder.encode([PatchOp<String>.unchanged]))
    XCTAssertThrowsError(try encoder.encode(UpdateOp<String?>.set(nil)))
    XCTAssertThrowsError(try encoder.encode(PatchOp<String?>.set(nil)))
    XCTAssertThrowsError(try decoder.decode(UpdateOp<String?>.self, from: Data("null".utf8)))
    XCTAssertEqual(try encoder.encode(PatchOp<String>.delete), Data("null".utf8))
    XCTAssertEqual(try encoder.encode(UpdateOp<[String?]>.set([nil])), Data("[null]".utf8))
  }

  func testLegacyOptionalHelpersStillOmitUnchanged() throws {
    struct Fields: Codable {
      var value: UpdateOp<String>?
      enum CodingKeys: String, CodingKey { case value }
      init(value: UpdateOp<String>?) { self.value = value }
      init(from decoder: Decoder) throws {
        value = try decoder.container(keyedBy: CodingKeys.self).decodeIfExists(String.self, forKey: .value)
      }
      func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfExists(value, forKey: .value)
      }
    }
    XCTAssertNil(try decoder.decode(Fields.self, from: Data("{}".utf8)).value)
    XCTAssertEqual(try encoder.encode(Fields(value: .unchanged)), Data("{}".utf8))
    XCTAssertThrowsError(try decoder.decode(Fields.self, from: Data(#"{"value":null}"#.utf8)))
  }

}
