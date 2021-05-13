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

  public init(type: URL, title: String, status: Int, detail: String, instance: URL?, parameters: [String: AnyValue]? = nil) {
    self.type = type
    self.title = title
    self.status = status
    self.detail = detail
    self.instance = instance
    self.parameters = parameters
  }

}


extension Problem: CustomStringConvertible {

  public var description: String {
    var output: [String] = []

    output.append("Type: \(type)")
    output.append("Title: \(title)")
    output.append("Status: \(status)")
    if let detail = detail {
      output.append("Detail: \(detail)")
    }
    if let instance = instance {
      output.append("Instance: \(instance)")
    }
    if let parameters = parameters, !parameters.isEmpty {
      output.append("Extended: \(parameters)")
    }

    return output.joined(separator: "\n")
  }

}


public extension MediaType {

  static let problem = MediaType(type: .application, tree: .standard, subtype: "problem", suffix: .json)

}

