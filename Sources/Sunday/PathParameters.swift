//
//  PathParameters.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import URITemplate


public struct PathParameters {

  private static var templateCache = [String: URITemplate]()
  private static let lock = NSRecursiveLock()

  public enum Error: Swift.Error {
    case missingParameterValue(name: String)
    case unsupportedParameterType(name: String, type: Any.Type)
  }

  public static func encode(_ path: String, with values: [String: Any]) throws -> String {

    let pathTemplate = try Self.template(for: path)

    var variables = [String: VariableValue]()

    for variableName in pathTemplate.variableNames {

      switch values[variableName] {
      case let value as CustomPathConvertible:
        variables[variableName] = value.pathDescription
      case let value as CustomStringConvertible:
        variables[variableName] = value.description
      case let value as VariableValue:
        variables[variableName] = value
      case nil:
        throw Error.missingParameterValue(name: variableName)
      case let value:
        throw Error.unsupportedParameterType(name: variableName, type: type(of: value))
      }

    }

    return try pathTemplate.process(variables: variables)
  }

  private static func template(for string: String) throws -> URITemplate {
    lock.lock(); defer { lock.unlock() }

    if let template = Self.templateCache[string] {
      return template
    }

    let template = try URITemplate(string: string)

    Self.templateCache[string] = template

    return template
  }

}
