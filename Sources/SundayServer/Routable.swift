//
//  Routable.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/16/19.
//  Copyright © 2019 Outfox, Inc. All rights reserved.
//

import Foundation
import Sunday
import URITemplate
import Regex


public enum RoutingError : Swift.Error {
  case invalidURL
  case parameterConversion(name: String)
}

public protocol Routable {

  func route(request: HTTP.Request, path: String, variables: [String: Any]) throws -> HTTP.Response?

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


public struct Routables : Routable {

  public let all: [Routable]

  public init(_ all: [Routable]) {
    self.all = all
  }

  public func route(request: HTTP.Request, path: String, variables: [String: Any]) throws -> HTTP.Response? {
    for routable in all {
      guard let response = try routable.route(request: request, path: path, variables: variables) else { continue }
      return response
    }
    return nil
  }

}
