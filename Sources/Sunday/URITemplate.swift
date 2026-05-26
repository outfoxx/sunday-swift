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
import ScreamURITemplate
import Synchronization

typealias HTTPParameters = Parameters

public extension URI {

  struct Template: ExpressibleByStringLiteral, Sendable {

    /// Marker protocol for values supported by URI template expansion.
    public protocol ParameterValue: Sendable {}

    public typealias Parameters = [String: (any Sendable)?]

    public enum Error: Swift.Error {
      case missingParameterValue(name: String)
      case unsupportedParameterType(name: String, type: Any.Type)
    }

    private static let cache = Mutex<[String: URITemplate]>([:])

    private static func cachedTemplate(for uri: String) throws -> URITemplate {
      try cache.withLock { storage in
        if let cached = storage[uri] {
          return cached
        }
        let template = try URITemplate(string: uri)
        storage[uri] = template
        return template
      }
    }

    public let format: String
    public let parameters: Parameters

    public init(format: String, parameters: Parameters = [:]) {
      self.format = format
      self.parameters = parameters
    }

    public init(stringLiteral format: String) {
      self.init(format: format)
    }

    /// Builds a complete URL with the provided path arguments
    ///
    /// - Parameters:
    ///   - relative: Template for the relative portion of the complete URL
    ///   - parameters: Parameters for the format; these take precedence
    ///     when encountering duplicates
    public func complete(
      relative: String = "",
      parameters: Parameters = [:],
      encoders: PathEncoders = .default
    ) throws -> URL {

      let full: String
      if relative == "" {
        full = format
      }
      else if format.hasSuffix("/") && relative.hasPrefix("/") {
        full = "\(format)\(relative.dropFirst())"
      }
      else if format.hasSuffix("/") || relative.hasPrefix("/") {
        full = "\(format)\(relative)"
      }
      else {
        full = "\(format)/\(relative)"
      }

      let impl = try Self.cachedTemplate(for: full)
      let parameters = self.parameters.merging(parameters) { $1 }
      var variables = [String: VariableValue]()

      for variableName in impl.variableNames {
        let value: any ParameterValue = switch parameters[variableName] {
        case .some(.some(let value)):
          try Self.requiredTemplateParameterValue(name: variableName, value)
        case .some(.none), nil:
          throw Error.missingParameterValue(name: variableName)
        }
        variables[variableName] = try variableValue(name: variableName, value: value, encoders: encoders)
      }

      let processedUrl = try impl.process(variables: variables)

      guard let url = URL(string: processedUrl) else {
        throw SundayError.invalidURL(URLComponents(string: processedUrl))
      }

      return url
    }

    static func parameters(from parameters: HTTPParameters) throws -> Parameters {
      try Dictionary(uniqueKeysWithValues: parameters.map { key, value in
        (key, try templateParameterValue(name: key, value))
      })
    }

    private static func templateParameterValue(
      name: String,
      _ value: (any Sendable)?
    ) throws -> (any ParameterValue)? {
      guard let value else {
        return nil
      }
      if let dictionary = value as? HTTPParameterDictionaryAdapter {
        return HTTPParameterDictionary(
          httpParameterValues: try Dictionary(uniqueKeysWithValues: dictionary.httpParameterValues.map { key, value in
            (key, try templateParameterValue(name: name, value))
          })
        )
      }
      if let array = value as? HTTPParameterArrayAdapter {
        return HTTPParameterArray(httpParameterValues: try array.httpParameterValues.compactMap { value in
          try templateParameterValue(name: name, value)
        })
      }
      if let value = value as? any ParameterValue {
        return value
      }
      if value is PathEncodable || value is LosslessStringConvertible || value is any RawRepresentable {
        return AnyTemplateParameterValue(name: name, value: value)
      }
      throw Error.unsupportedParameterType(name: name, type: type(of: value))
    }

    private static func requiredTemplateParameterValue(
      name: String,
      _ value: any Sendable
    ) throws -> any ParameterValue {
      guard let value = try templateParameterValue(name: name, value) else {
        throw Error.unsupportedParameterType(name: name, type: type(of: value))
      }
      return value
    }

    private func variableValue(
      name: String,
      value: any ParameterValue,
      encoders: PathEncoders
    ) throws -> VariableValue {

      if let converted = encoders.firstSupported(value: value) {
        return converted
      }
      if let dictionary = value as? HTTPParameterDictionaryAdapter {
        return try Dictionary(uniqueKeysWithValues: dictionary.httpParameterValues.compactMap { key, value in
          guard let value else {
            return nil
          }
          return (key, try scalarVariableValue(name: name, value: value, encoders: encoders))
        })
      }
      if let array = value as? HTTPParameterArrayAdapter {
        return try array.httpParameterValues.map { value in
          try scalarVariableValue(name: name, value: value, encoders: encoders)
        }
      }
      if let variableValue = value as? VariableValue {
        return variableValue
      }
      return try scalarVariableValue(name: name, value: value, encoders: encoders)
    }

    private func scalarVariableValue(
      name: String,
      value: any Sendable,
      encoders: PathEncoders
    ) throws -> StringVariableValue {

      if let converted = encoders.firstSupported(value: value) {
        return converted
      }
      if let stringValue = value as? StringVariableValue {
        return stringValue
      }
      if let pathValue = value as? PathEncodable {
        return pathValue.pathDescription
      }
      if let value = value as? AnyTemplateParameterValue {
        return try scalarString(value)
      }
      if let losslessValue = value as? LosslessStringConvertible {
        return losslessValue.description
      }
      if let rawRepValue = value as? any RawRepresentable {
        return String(describing: rawRepValue.rawValue)
      }
      throw Error.unsupportedParameterType(name: name, type: type(of: value))
    }

    private func scalarString(_ value: AnyTemplateParameterValue) throws -> String {
      if let pathValue = value.value as? PathEncodable {
        return pathValue.pathDescription
      }
      if let stringValue = value.value as? LosslessStringConvertible {
        return stringValue.description
      }
      if let rawValue = value.value as? any RawRepresentable {
        return String(describing: rawValue.rawValue)
      }
      throw Error.unsupportedParameterType(name: value.name, type: type(of: value.value))
    }

  }

}

private struct AnyTemplateParameterValue: URI.Template.ParameterValue {
  let name: String
  let value: any Sendable
}
