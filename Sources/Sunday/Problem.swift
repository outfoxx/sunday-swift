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
public struct Problem: Error {

  public let status: Int

  public let title: String

  public let detail: String?

  public let instance: String?

  public let type: URL?

  public let extended: [String: AnyValue]?

}


extension Problem: Encodable {}
extension Problem: Decodable {}


extension Problem: CustomStringConvertible {

  public var description: String {
    var output: [String] = []

    output.append("Status: \(status)")
    output.append("Title: \(title)")
    output.append("Detail: " + (detail != nil ? "\(detail!)" : "nil"))
    output.append("Instance: " + (instance != nil ? "\(instance!)" : "nil"))
    output.append("Type: " + (type != nil ? "\(type!)" : "nil"))
    if let extended = extended {
      if !extended.isEmpty {
        output.append("Extended: \(extended)")
      }
    }

    return output.joined(separator: "\n")
  }

}


public extension MediaType {

  static let problem = MediaType(type: .application, tree: .standard, subtype: "problem", suffix: .json)

}
