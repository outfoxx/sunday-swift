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
public class Problem: Error, Codable {

  public let type: URL

  public let title: String

  public let status: Int

  public let detail: String?

  public let instance: URL?

  public let parameters: [String: AnyValue]?

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
  
  public convenience init(statusCode: Int) {
    self.init(type: URL(string: "about:blank")!, title: Self.statusTitle(statusCode: statusCode), status: statusCode)
  }
  
  public convenience init(statusCode: Int, data: [String: AnyValue]) {
    var data = data
    let type = URL(string: "about:blank")!
    let title = data.removeValue(forKey: "title")?.stringValue ?? Problem.statusTitle(statusCode: statusCode)
    let detail = data.removeValue(forKey: "detail")?.stringValue
    let instance = data.removeValue(forKey: "instance")?.stringValue.map { URL(string: $0) } ?? nil
    self.init(type: type, title: title, status: statusCode, detail: detail, instance: instance, parameters: data)
  }
  
  public static func statusTitle(statusCode: Int) -> String {
    return HTTP.StatusCode(rawValue: statusCode).map { HTTP.statusText[$0]! } ?? "Unknown"
  }

}


extension Problem: CustomStringConvertible {

  public var description: String {
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
      builder = builder.add(parameters, named: "parameters")
    }
    return builder.build()
  }

}


public extension MediaType {

  static let problem = MediaType(type: .application, tree: .standard, subtype: "problem", suffix: .json)

}
