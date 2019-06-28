//
//  Problem.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/18/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
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

  let status: Int

  let title: String

  let detail: String?

  let instance: String?

  let type: URL?

  let extended: [String: AnyValue]?

}


extension Problem : Encodable {}
extension Problem : Decodable {}


extension Problem : CustomStringConvertible {

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
