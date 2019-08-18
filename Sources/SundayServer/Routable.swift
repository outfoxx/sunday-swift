//
//  Routable.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

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
public struct RoutableBuilder {

  public static func buildBlock(_ routables: Routable...) -> Routable {
    return Routables(routables)
  }

  public static func buildBlock(_ a: [Routable], _ b: [Routable]) -> Routable {
    return Routables(a + b)
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
