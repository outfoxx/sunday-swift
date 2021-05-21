//
//  Problem.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCodables


/**
 * Problem details for HTTP APIs
 *
 * Swift `Error` compatible `struct` for RFC 7807 with the
 * media type `application/problem+json`.
 */
open class Problem: Error, Codable {
  
  public let type: URL

  public let title: String

  public let status: Int

  public let detail: String?

  public let instance: URL?

  public let parameters: [String: AnyValue]?
  
  public var statusCode: HTTP.StatusCode? {
    HTTP.StatusCode(rawValue: status)
  }

  public init(
    type: URL,
    title: String,
    status: Int,
    detail: String? = nil,
    instance: URL? = nil,
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
    type: URL,
    title: String,
    statusCode: HTTP.StatusCode,
    detail: String? = nil,
    instance: URL? = nil,
    parameters: [String: AnyValue]? = nil
  ) {
    self.type = type
    self.title = title
    self.status = statusCode.rawValue
    self.detail = detail
    self.instance = instance
    self.parameters = parameters
  }

  public convenience init(statusCode: Int) {
    self.init(type: URL(string: "about:blank")!, title: Self.statusTitle(statusCode: statusCode), status: statusCode)
  }
  
  public convenience init(statusCode: HTTP.StatusCode) {
    self.init(statusCode: statusCode.rawValue)
  }

  public convenience init(statusCode: Int, data: [String: AnyValue]) {
    var data = data
    let type = (data.removeValue(forKey: "type")?.stringValue.map { URL(string: $0) } ?? Self.stdType) ?? Self.stdType
    let title = data.removeValue(forKey: "title")?.stringValue ?? Problem.statusTitle(statusCode: statusCode)
    let detail = data.removeValue(forKey: "detail")?.stringValue
    let instance = data.removeValue(forKey: "instance")?.stringValue.map { URL(string: $0) } ?? nil
    let parameters = data.isEmpty ? nil : data
    self.init(type: type, title: title, status: statusCode, detail: detail, instance: instance, parameters: parameters)
  }

  public convenience init(statusCode: HTTP.StatusCode, data: [String: AnyValue]) {
    self.init(statusCode: statusCode.rawValue, data: data)
  }

  public required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    
    var decodedType: URL?
    var decodedTitle: String?
    var decodedStatus: Int?
    var detail: String?
    var instance: URL?
    var parameters: [String: AnyValue] = [:]
    
    let isCustom = Swift.type(of: self) != Problem.self
    
    for key in container.allKeys {
      switch (key) {
      case CodingKeys.type:
        decodedType = try container.decode(URL.self, forKey: key)
        
      case CodingKeys.title:
        decodedTitle = try container.decode(String.self, forKey: key)
        
      case CodingKeys.status:
        decodedStatus = try container.decode(Int.self, forKey: key)
        
      case CodingKeys.detail:
        detail = try container.decodeIfPresent(String.self, forKey: key)
        
      case CodingKeys.instance:
        instance = try container.decodeIfPresent(URL.self, forKey: key)
        
      default:
        if !isCustom {
          parameters[key.stringValue] = try container.decode(AnyValue.self, forKey: key)
        }
      }
    }
    
    guard let type = decodedType else {
      throw DecodingError.dataCorruptedError(forKey: CodingKeys.type, in: container,
                                             debugDescription: "Required Value Missing")
    }
    
    guard let title = decodedTitle else {
      throw DecodingError.dataCorruptedError(forKey: CodingKeys.title, in: container,
                                             debugDescription: "Required Value Missing")
    }
    
    guard let status = decodedStatus else {
      throw DecodingError.dataCorruptedError(forKey: CodingKeys.status, in: container,
                                             debugDescription: "Required Value Missing")
    }

    self.type = type
    self.title = title
    self.status = status
    self.detail = detail
    self.instance = instance
    self.parameters = parameters.isEmpty ? nil : parameters
  }
  
  open func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AnyCodingKey.self)
    try container.encode(type, forKey: CodingKeys.type)
    try container.encode(title, forKey: CodingKeys.title)
    try container.encode(status, forKey: CodingKeys.status)
    try container.encode(detail, forKey: CodingKeys.detail)
    try container.encode(instance, forKey: CodingKeys.instance)
    try parameters?.forEach { key, value in
      try container.encode(value, forKey: AnyCodingKey(stringValue: key, intValue: nil))
    }
  }

  public static func statusTitle(statusCode: Int) -> String {
    return HTTP.StatusCode(rawValue: statusCode).map { HTTP.statusText[$0]! } ?? "Unknown"
  }
  
  private struct CodingKeys {
    static let type = AnyCodingKey("type")
    static let title = AnyCodingKey("title")
    static let status = AnyCodingKey("status")
    static let detail = AnyCodingKey("detail")
    static let instance = AnyCodingKey("instance")
  }
  
  private static let stdType = URL(string: "about:blank")!

}


extension Problem: CustomStringConvertible {

  open var description: String {
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


public extension MediaType {

  static let problem = MediaType(type: .application, tree: .standard, subtype: "problem", suffix: .json)

}
