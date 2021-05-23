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

public extension URI {

  struct Template: ExpressibleByStringLiteral {

    public enum Error: Swift.Error {
      case missingParameterValue(name: String)
      case unsupportedParameterType(name: String, type: Any.Type)
    }

    private static var implCache = [String: URITemplate]()
    private static let lock = NSRecursiveLock()

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
    public func complete(relative: String = "", parameters: Parameters = [:]) throws -> URL {

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

      let impl = try Self.impl(for: full)
      let parameters = self.parameters.merging(parameters) { $1 }
      var variables = [String: VariableValue]()

      for variableName in impl.variableNames {

        switch parameters[variableName] {
        case let value as CustomPathConvertible:
          variables[variableName] = value.pathDescription
        case let value as VariableValue:
          variables[variableName] = value
        case let value as LosslessStringConvertible:
          variables[variableName] = value.description
        case nil:
          throw Error.missingParameterValue(name: variableName)
        case let value:
          throw Error.unsupportedParameterType(name: variableName, type: type(of: value))
        }

      }

      let processedUrl = try impl.process(variables: variables)

      guard let url = URL(string: processedUrl) else {
        throw SundayError.invalidURL(URLComponents(string: processedUrl))
      }

      return url
    }

    private static func impl(for string: String) throws -> URITemplate {
      lock.lock(); defer { lock.unlock() }

      if let impl = Self.implCache[string] {
        return impl
      }

      let impl = try URITemplate(string: string)

      Self.implCache[string] = impl

      return impl
    }

  }

}
