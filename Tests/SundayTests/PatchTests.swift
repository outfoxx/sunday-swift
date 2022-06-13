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


public struct Security: Equatable, Codable {

  var type: UpdateOp<String>? = .none
  var enc: PatchOp<Data>? = .none
  var sig: PatchOp<Data>? = .none

  public init(
    type: UpdateOp<String>? = .none,
    enc: PatchOp<Data>? = .none,
    sig: PatchOp<Data>? = .none
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
    self.type = try container.decodeIfExists(String.self, forKey: .type)
    self.enc = try container.decodeIfExists(Data.self, forKey: .enc)
    self.sig = try container.decodeIfExists(Data.self, forKey: .sig)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfExists(self.type, forKey: .type)
    try container.encodeIfExists(self.enc, forKey: .enc)
    try container.encodeIfExists(self.sig, forKey: .sig)
  }
}

extension AnyPatchOp where Value == Security {

  static func merge(
    type: UpdateOp<String>? = .none,
    enc: PatchOp<Data>? = .none,
    sig: PatchOp<Data>? = .none
  ) -> Self {
    Self.merge(Security(type: type, enc: enc, sig: sig))
  }

}

public struct Device: Codable, Equatable {

  var name: UpdateOp<String>? = .none
  var security: UpdateOp<Security>? = .none
  var url: PatchOp<URL>? = .none
  var data: PatchOp<[String: String]>? = .none

  public init(
    name: UpdateOp<String>? = .none,
    security: UpdateOp<Security>? = .none,
    url: PatchOp<URL>? = .none,
    data: PatchOp<[String: String]>? = .none
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
    self.name = try container.decodeIfExists(String.self, forKey: .name)
    self.security = try container.decodeIfExists(Security.self, forKey: .security)
    self.url = try container.decodeIfExists(URL.self, forKey: .url)
    self.data = try container.decodeIfExists([String: String].self, forKey: .data)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfExists(self.name, forKey: .name)
    try container.encodeIfExists(self.security, forKey: .security)
    try container.encodeIfExists(self.url, forKey: .url)
    try container.encodeIfExists(self.data, forKey: .data)
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
      data: .none
    )

    let json = #"{"name":"Test","security":{"enc":"AQID","sig":null,"type":"17"}}"#.data(using: .utf8)!

    XCTAssertEqual(try encoder.encode(patch), json)

    let decodedPatch = try decoder.decode(Device.self, from: json)
    XCTAssertEqual(decodedPatch, patch)


    let encodedJSON = try encoder.encode(decodedPatch)
    XCTAssertEqual(encodedJSON, json)
  }

}
