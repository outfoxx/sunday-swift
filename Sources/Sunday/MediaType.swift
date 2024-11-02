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
import Regex


/**
 * Media type (aka MIME type) that supports parsing from
 * text along with equality and compatibility comparisons
 * that properly account for types with parameters.
 **/
public struct MediaType {

  public enum Error: Swift.Error {
    case invalid
  }

  public enum StandardParameterName: String {
    case charSet = "charset"
  }

  public enum `Type`: String, CaseIterable, Equatable, Hashable, Codable {
    case application
    case audio
    case example
    case font
    case image
    case message
    case model
    case multipart
    case text
    case video
    case any = "*"
  }

  public enum Tree: String, CaseIterable, Equatable, Hashable, Codable {
    case standard = ""
    case vendor = "vnd."
    case personal = "prs."
    case unregistered = "x."
    case obsolete = "x-"
    case any = "*"
  }

  public struct Suffix: RawRepresentable, Equatable, Hashable, Codable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(_ value: String) {
      self.rawValue = value
    }

    public init(stringLiteral value: StringLiteralType) {
      self.rawValue = value
    }

    var value: String { rawValue }

    public static func suffix(_ suffix: String) -> Suffix { Suffix(rawValue: suffix) }

    public static let xml = suffix("xml")
    public static let json = suffix("json")
    public static let ber = suffix("ber")
    public static let der = suffix("der")
    public static let fastinfoset = suffix("fastinfoset")
    public static let wbxml = suffix("wbxml")
    public static let zip = suffix("zip")
    public static let cbor = suffix("cbor")
  }

  public let type: `Type`
  public let tree: Tree
  public let subtype: String
  public let suffix: Suffix?
  public let parameters: [String: String]

  public init(
    type: Type,
    tree: Tree = .standard,
    subtype: String = "*",
    suffix: Suffix? = nil,
    parameters: [String: String] = [:]
  ) {
    self.type = type
    self.tree = tree
    self.subtype = subtype.lowercased()
    self.suffix = suffix
    self
      .parameters = Dictionary(uniqueKeysWithValues: parameters.map { key, value in
        (key.lowercased(), value.lowercased())
      })
  }

  public static func from(accept headers: [String]) -> [MediaType] {
    return headers.flatMap { header in header.components(separatedBy: ",") }.compactMap { MediaType($0) }
  }

  private static let fullRegex = Regex(
    // swiftlint:disable:next line_length
    ##"^((?:[a-z]+|\*))\/(x(?:-|\\.)|(?:(?:vnd|prs|x)\.)|\*)?([a-z0-9\-\.]+|\*)(?:\+([a-z]+))?( *(?:; *(?:(?:[\w\.-]+) *= *(?:[\w\.-]+)) *)*)$"##,
    options: [.ignoreCase]
  )
  private static let paramRegex = Regex(##" *; *([\w\.-]+) *= *([\w\.-]+)"##, options: [.ignoreCase])

  public init(valid: String) throws {
    guard let valid = MediaType(valid) else {
      throw Error.invalid
    }
    self = valid
  }

  public init?(_ string: String) {
    guard let match = Self.fullRegex.firstMatch(in: string) else { return nil }

    guard let typeVal = match.captures[0]?.lowercased(), let type = `Type`(rawValue: typeVal) else {
      return nil
    }
    self.type = type

    if let treeVal = match.captures[1]?.lowercased(), let tree = Tree(rawValue: treeVal) {
      self.tree = tree
    }
    else {
      tree = .standard
    }

    guard let subtype = match.captures[2]?.lowercased() else {
      return nil
    }
    self.subtype = subtype

    if let suffixVal = match.captures[3]?.lowercased() {
      self.suffix = .init(suffixVal)
    }
    else {
      suffix = nil
    }

    if let encodedParameters = match.captures[4] {
      parameters = Dictionary(
        uniqueKeysWithValues:
        Self.paramRegex.allMatches(in: encodedParameters)
          .compactMap { parameterMatch -> (String, String)? in
            guard let key = parameterMatch.captures[0], let value = parameterMatch.captures[1] else { return nil }
            return (key.lowercased(), value.lowercased())
          }
      )
    }
    else {
      parameters = [:]
    }
  }

  public func parameter(_ name: StandardParameterName) -> String? {
    return parameters[name.rawValue]
  }

  public func parameter(_ name: String) -> String? {
    return parameters[name]
  }

  public func with(
    type: Type? = nil,
    tree: Tree? = nil,
    subtype: String? = nil,
    parameters: [String: String]? = nil
  ) -> MediaType {
    let type = type ?? self.type
    let tree = tree ?? self.tree
    let subtype = subtype?.lowercased() ?? self.subtype
    let parameters = self.parameters.merging(parameters ?? [:]) { _, override in override }
    return MediaType(type: type, tree: tree, subtype: subtype, suffix: suffix, parameters: parameters)
  }

  public func with(_ value: String, forParameter name: StandardParameterName) -> MediaType {
    return with(parameters: [name.rawValue: value])
  }

  public func with(_ value: String, forParameter name: String) -> MediaType {
    return with(parameters: [name: value])
  }

  public var value: String {
    let type = self.type.rawValue
    let tree = self.tree.rawValue
    let suffix = self.suffix.map { "+\($0.value)" } ?? ""
    let parameters = self.parameters.keys.sorted().map { key in ";\(key)=\(self.parameters[key]!)" }.joined()
    return "\(type)/\(tree)\(subtype)\(suffix)\(parameters)"
  }

  public static let plain = MediaType(type: .text, subtype: "plain")
  public static let html = MediaType(type: .text, subtype: "html")
  public static let json = MediaType(type: .application, subtype: "json")
  public static let yaml = MediaType(type: .application, subtype: "json")
  public static let cbor = MediaType(type: .application, subtype: "cbor")
  public static let eventStream = MediaType(type: .text, subtype: "event-stream")
  public static let octetStream = MediaType(type: .application, subtype: "octet-stream")
  public static let wwwFormUrlEncoded = MediaType(type: .application, tree: .obsolete, subtype: "www-form-urlencoded")

  public static let any = MediaType(type: .any, subtype: "*")
  public static let anyText = MediaType(type: .text, subtype: "*")
  public static let anyImage = MediaType(type: .image, subtype: "*")
  public static let anyAudio = MediaType(type: .audio, subtype: "*")
  public static let anyVideo = MediaType(type: .video, subtype: "*")

  public static let x509CACert = MediaType(type: .application, tree: .obsolete, subtype: "x509-ca-cert")
  public static let x509UserCert = MediaType(type: .application, tree: .obsolete, subtype: "x509-user-cert")

  public static let jsonStructured = MediaType(type: .any, tree: .any, subtype: "*", suffix: .json)
  public static let xmlStructured = MediaType(type: .any, tree: .any, subtype: "*", suffix: .xml)

}


extension MediaType: Equatable, Hashable {}

extension MediaType: Codable {

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let source = MediaType(value) else {
      throw Error.invalid
    }
    self = source
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }

}


public extension MediaType {

  static func compatible(lhs: MediaType, rhs: MediaType) -> Bool {
    if lhs.type != .any, rhs.type != .any, lhs.type != rhs.type {
      return false
    }
    if lhs.tree != .any, rhs.tree != .any, lhs.tree != rhs.tree {
      return false
    }
    if lhs.subtype != "*", rhs.subtype != "*", lhs.subtype != rhs.subtype {
      return false
    }
    if lhs.suffix != rhs.suffix {
      return false
    }
    return Set(lhs.parameters.keys).intersection(rhs.parameters.keys)
      .allSatisfy { lhs.parameters[$0] == rhs.parameters[$0] }
  }

}

public func ~= (pattern: MediaType, value: MediaType) -> Bool {
  return MediaType.compatible(lhs: pattern, rhs: value)
}

public func ~= (pattern: String, value: MediaType) -> Bool {
  guard let pattern = MediaType(pattern) else { return false }
  return MediaType.compatible(lhs: pattern, rhs: value)
}

public func ~= (pattern: MediaType, value: String) -> Bool {
  guard let value = MediaType(value) else { return false }
  return MediaType.compatible(lhs: pattern, rhs: value)
}



extension MediaType: CustomStringConvertible, LosslessStringConvertible {

  public var description: String {
    return value
  }

}
