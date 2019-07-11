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

  public func route(request: HTTP.Request, path: String, variables: [String: Any]) throws -> HTTP.Response? {
    guard let match = matcher.firstMatch(in: path) else { return nil }

    let path = match.captures.last! ?? ""
    var variables = variables
    for (name, value) in zip(variableNames, match.captures.dropLast()) {
      variables[name] = value!
    }

    return try routable.route(request: request, path: path, variables: variables)
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

  public typealias Handler = (HTTP.Request, String, [String: Any]) throws -> HTTP.Response?

  private let handler: Handler

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  public func route(request: HTTP.Request, path: String, variables: [String: Any]) throws -> HTTP.Response? {
    return try handler(request, path, variables)
  }

}


public struct Trace : Routable {

  public typealias Handler = (HTTP.Request, String, [String: Any]) throws -> HTTP.Response?

  private let routable: Routable

  public init(@RoutableBuilder routableBuilder: () -> Routable) {
    self.routable = routableBuilder()
  }

  public func route(request: HTTP.Request, path: String, variables: [String: Any]) throws -> HTTP.Response? {
    guard let response = try routable.route(request: request, path: path, variables: variables) else {
      return nil
    }
    print("Routed: \(request.url)")
    return response
  }

}
