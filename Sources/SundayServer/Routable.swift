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
import Sunday


public enum RoutingError: Swift.Error {
  case invalidURL
  case parameterConversionFailed(name: String, error: Error)
  case missingRequiredParameter(name: String)
}

public struct Route {
  let matched: String
  let unmatched: String
  let parameters: [String: String]
}

public typealias RouteHandler = (Route, HTTPRequest, HTTPResponse) throws -> Void
public typealias RouteResult = (route: Route, handler: RouteHandler)

public protocol Routable {

  func route(_ route: Route, request: HTTPRequest) throws -> RouteResult?

}


@_functionBuilder
public enum RoutableBuilder {

  public static func buildBlock(_ routables: Routable...) -> Routable {
    return Routables(routables)
  }

  public static func buildBlock(_ first: [Routable], _ second: [Routable]) -> Routable {
    return Routables(first + second)
  }

}


public struct Routables: Routable {

  public let all: [Routable]

  public init(_ all: [Routable]) {
    self.all = all
  }

  public func route(_ route: Route, request: HTTPRequest) throws -> RouteResult? {
    for routable in all {
      guard let response = try routable.route(route, request: request) else { continue }
      return response
    }
    return nil
  }

}
