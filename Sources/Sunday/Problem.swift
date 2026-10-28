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


/**
 * Problem details for HTTP APIs
 *
 * Swift `Error` compatible protocol for RFC 9457 with the
 * media type `application/problem+json`.
 */
public protocol Problem: Error, Codable, CustomStringConvertible, Sendable {

  var type: String { get }

  var title: String? { get }

  var status: Int? { get }

  var detail: String? { get }

  var instance: String? { get }

  var parameters: [String: AnyValue]? { get }

}


public extension Problem {

  /// Foundation URL representation, when the type reference is representable as a URL.
  var typeURI: URL? { URL(string: type) }

  /// Foundation URL representation, when the instance reference is representable as a URL.
  var instanceURI: URL? { instance.flatMap(URL.init(string:)) }

  /**
   * HTTP status code matching the problem status.
   */
  var statusCode: HTTP.StatusCode? {
    status.flatMap(HTTP.StatusCode.init(rawValue:))
  }

  /**
   * Text representation of the problem details.
   */
  var description: String {
    var builder =
      DescriptionBuilder(Self.self)
        .add(type, named: "type")
        .add(title, named: "title")
        .add(status, named: "status")
    if let detail = detail {
      builder = builder.add(detail, named: "detail")
    }
    if let instance = instance {
      builder = builder.add(instance, named: "instance")
    }
    if let parameters = parameters, !parameters.isEmpty {
      builder = builder.add(parameters.mapValues { $0.unwrappedValues }, named: "parameters")
    }
    return builder.build()
  }

}


/**
 * Generic RFC 9457 problem details value.
 */
public struct GenericProblem: Problem {

  public let type: String
  public let title: String?
  public let status: Int?
  public let detail: String?
  public let instance: String?
  public let parameters: [String: AnyValue]?

  public init(
    type: String,
    title: String? = nil,
    status: Int? = nil,
    detail: String? = nil,
    instance: String? = nil,
    parameters: [String: AnyValue]? = nil
  ) {
    self.type = type
    self.title = title
    self.status = status
    self.detail = detail
    self.instance = instance
    self.parameters = parameters
  }

  public init(
    type: String,
    title: String,
    statusCode: HTTP.StatusCode,
    detail: String? = nil,
    instance: String? = nil,
    parameters: [String: AnyValue]? = nil
  ) {
    self.init(
      type: type,
      title: title,
      status: statusCode.rawValue,
      detail: detail,
      instance: instance,
      parameters: parameters
    )
  }

  /// Creates a Problem from Foundation URLs while retaining strings as its wire representation.
  public init(
    type: URL,
    title: String? = nil,
    status: Int? = nil,
    detail: String? = nil,
    instance: URL? = nil,
    parameters: [String: AnyValue]? = nil
  ) {
    self.init(type: type.absoluteString, title: title, status: status, detail: detail,
      instance: instance?.absoluteString, parameters: parameters)
  }

  public init(statusCode: Int) {
    self.init(type: Self.stdType, title: Self.statusTitle(statusCode: statusCode), status: statusCode)
  }

  public init(statusCode: HTTP.StatusCode) {
    self.init(statusCode: statusCode.rawValue)
  }

  /// Decodes standard members with the same rules as Codable, then applies HTTP defaults.
  public init(statusCode: Int, data: [String: AnyValue]) throws {
    let tree = AnyValue.dictionary(.init(uniqueKeysWithValues: data.map { (.string($0.key), $0.value) }))
    let problem = try AnyValueDecoder().decode(GenericProblem.self, from: tree)
    let status = problem.status ?? statusCode
    self.init(type: problem.type,
      title: problem.title ?? (problem.type == Self.stdType ? Self.statusTitle(statusCode: status) : nil),
      status: status, detail: problem.detail, instance: problem.instance, parameters: problem.parameters)
  }

  /// Decodes a Problem with HTTP context, retaining a valid body status.
  public init(statusCode: HTTP.StatusCode, data: [String: AnyValue]) throws {
    try self.init(statusCode: statusCode.rawValue, data: data)
  }

  public init(from decoder: Decoder) throws {
    let decoder = try ProblemDecoding.normalized(decoder)
    let container = try decoder.container(keyedBy: AnyCodingKey.self)

    var decodedType: String?
    var decodedTitle: String?
    var decodedStatus: Int?
    var detail: String?
    var instance: String?
    var parameters: [String: AnyValue] = [:]

    for key in container.allKeys {
      switch key {
      case CodingKeys.type:
        decodedType = try container.decode(String.self, forKey: key)

      case CodingKeys.title:
        decodedTitle = try container.decode(String.self, forKey: key)

      case CodingKeys.status:
        decodedStatus = try container.decode(Int.self, forKey: key)

      case CodingKeys.detail:
        detail = try container.decodeIfPresent(String.self, forKey: key)

      case CodingKeys.instance:
        instance = try container.decodeIfPresent(String.self, forKey: key)

      default:
        parameters[key.stringValue] = try container.decode(AnyValue.self, forKey: key)
      }
    }

    self.init(
      type: decodedType ?? Self.stdType,
      title: decodedTitle,
      status: decodedStatus,
      detail: detail,
      instance: instance,
      parameters: parameters.isEmpty ? nil : parameters
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AnyCodingKey.self)
    try container.encode(type, forKey: CodingKeys.type)
    try container.encodeIfPresent(title, forKey: CodingKeys.title)
    try container.encodeIfPresent(status, forKey: CodingKeys.status)
    try container.encodeIfPresent(detail, forKey: CodingKeys.detail)
    try container.encodeIfPresent(instance, forKey: CodingKeys.instance)
    try parameters?.forEach { key, value in
      try container.encode(value, forKey: AnyCodingKey(stringValue: key, intValue: nil))
    }
  }

  public static func statusTitle(statusCode: Int) -> String {
    return HTTP.StatusCode(rawValue: statusCode).flatMap { HTTP.statusText[$0] } ?? "Unknown"
  }

  private enum CodingKeys {
    static let type = AnyCodingKey("type")
    static let title = AnyCodingKey("title")
    static let status = AnyCodingKey("status")
    static let detail = AnyCodingKey("detail")
    static let instance = AnyCodingKey("instance")
  }

  private static let stdType = "about:blank"


}


public extension HTTP {

  /**
   * Basic HTTP status problem for responses without problem details.
   */
  typealias StatusProblem = GenericProblem

}


public extension MediaType {

  static let problem = MediaType(type: .application, tree: .standard, subtype: "problem", suffix: .json)

}
