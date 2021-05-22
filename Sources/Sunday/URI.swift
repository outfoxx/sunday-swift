//
//  URI.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import URITemplate

public struct URI: Equatable, Hashable {

  public enum Error: Swift.Error {
    case invalidURI
  }

  private let components: URLComponents

  public var scheme: String { components.scheme! }
  public var host: String? { components.host }
  public var path: String { components.path }
  public var query: String? { components.query }
  public var queryItems: [URLQueryItem]? { components.queryItems }
  public var fragment: String? { components.fragment }

  public init(string: String) throws {
    guard let components = URLComponents(string: string) else {
      throw Error.invalidURI
    }
    self.init(components: components)
  }

  public init(scheme: String, host: String, path: String, queryItems: [URLQueryItem] = [], fragment: String? = nil) {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path
    components.queryItems = queryItems
    components.fragment = fragment
    self.init(components: components)
  }

  public init(components: URLComponents) {
    self.components = components
  }

}

extension URI: Codable {

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(string: container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(components.string!)
  }

}
