//
//  RoutablePath.swift
//  
//
//  Created by Kevin Wooten on 6/28/19.
//

import Foundation
import Sunday
import Regex


public struct Path : Routable {

  public let variableNames: [String]
  public let matcher: Regex
  public let routable: Routable

  public init(_ template: String, @RoutableBuilder _ buildRoutable: () -> Routable) {
    self.variableNames = Self.pathVariableNames(for: template)
    self.matcher = Self.pathMatcher(for: template)
    self.routable = buildRoutable()
  }

  public func route(_ route: Route, request: HTTPRequest) throws -> RouteResult? {
    guard let match = matcher.firstMatch(in: route.unmatched) else { return nil }

    let matched = match.captures.dropLast().compactMap { $0 }.joined(separator: "")
    let unmatched = match.captures.last! ?? ""
    var paraeters = route.parameters

    for (name, value) in zip(variableNames, match.captures.dropLast()) {
      paraeters[name] = value!
    }

    return try routable.route(Route(matched: matched,
                                    unmatched: unmatched,
                                    parameters: paraeters),
                              request: request)
  }

  private static let variableMatcher = Regex(#"\{([_a-zA-Z][_a-zA-Z0-9]*)\}?"#)

  private static func pathVariableNames(for template: String) -> [String] {
    return variableMatcher.allMatches(in: template).map { $0.captures[0] ?? "" }
  }

  private static func pathMatcher(for template: String) -> Regex {
    let pathPattern = template.replacingAll(matching: variableMatcher, with: #"([^/]*)"#)
    return try! Regex(string: "^\(pathPattern)(.*)$")
  }

}


public struct CatchAll : Routable {

  private let handler: RouteHandler

  public init(handler: @escaping RouteHandler) {
    self.handler = handler
  }

  public func route(_ route: Route, request: HTTPRequest) throws -> RouteResult? {
    return (route, handler)
  }

}


public struct Trace : Routable {

  private let routable: Routable

  public init(@RoutableBuilder routableBuilder: () -> Routable) {
    self.routable = routableBuilder()
  }

  public func route(_ route: Route, request: HTTPRequest) throws -> RouteResult? {
    guard let result = try routable.route(route, request: request) else {
      return nil
    }
    print("Routed: \(request.url)")
    return result
  }

}
