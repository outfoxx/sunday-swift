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
import URITemplate

public struct URI: Equatable, Hashable {

  public enum Error: Swift.Error {
    case invalidURI
  }

  private let components: URLComponents

  public var scheme: String? { components.scheme }
  public var host: String? { components.host }
  public var port: Int? { components.port }
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

  public init(
    scheme: String? = nil,
    host: String? = nil,
    path: String,
    queryItems: [URLQueryItem]? = nil,
    fragment: String? = nil
  ) {
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
    guard let string = components.string else {
      let context = EncodingError.Context(
        codingPath: encoder.codingPath,
        debugDescription: "Unable to get string for URI",
        underlyingError: nil
      )
      throw EncodingError.invalidValue(self, context)
    }
    var container = encoder.singleValueContainer()
    try container.encode(string)
  }

}
