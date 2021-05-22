//
//  Description.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


/**
 * Builder for simplifying the generation of description
 * values for types implementing `CustomStringConvertible`
 */
public struct DescriptionBuilder {

  private var name: String
  private var entries = [(String, Any?)]()

  private init(_ name: String, _ entries: [(String, Any?)] = []) {
    self.name = name
    self.entries = entries
  }

  public init(_ type: Any.Type) {
    self.init(String(describing: type))
  }

  public func add(_ value: Any?, named name: String) -> DescriptionBuilder {
    var entries = self.entries
    entries.append((name, value))
    return DescriptionBuilder(self.name, entries)
  }

  public func build() -> String {
    return "\(name)(\(entries.map { "\($0)=\($1 ?? "nil")" }.joined(separator: ", ")))"
  }

}
