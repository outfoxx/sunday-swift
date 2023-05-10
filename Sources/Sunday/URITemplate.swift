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

    private class Cache {

      private var storage: [String: URITemplate] = [:]
      private var lockQueue = DispatchQueue(label: "URI.Template.Cache Lock")

      func get(uri: String) throws -> URITemplate {
        try lockQueue.sync {
          if let cached = storage[uri] {
            return cached
          }
          let template = try URITemplate(string: uri)
          storage[uri] = template
          return template
        }
      }
    }

    private static let cache = Cache()

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

      let impl = try Self.cache.get(uri: full)
      let parameters = self.parameters.merging(parameters) { $1 }
      var variables = [String: VariableValue]()

      for variableName in impl.variableNames {

        switch parameters[variableName] {
        case let value as VariableValue:
          variables[variableName] = value
        case .some(.some(let value)):
          guard let converted = encoders.firstSupported(value: value) else {
            if let pathValue = value as? PathEncodable {
              variables[variableName] = pathValue.pathDescription
              continue
            }
            else if let losslessValue = value as? LosslessStringConvertible {
              variables[variableName] = losslessValue.description
              continue
            }
            else if let rawRepValue = value as? any RawRepresentable {
              variables[variableName] = String(describing: rawRepValue.rawValue)
              continue
            }
            throw Error.unsupportedParameterType(name: variableName, type: type(of: value))
          }
          variables[variableName] = converted
        case nil:
          throw Error.missingParameterValue(name: variableName)
        default:
          throw Error.unsupportedParameterType(name: variableName, type: type(of: parameters[variableName]))
        }

      }

      let processedUrl = try impl.process(variables: variables)

      guard let url = URL(string: processedUrl) else {
        throw SundayError.invalidURL(URLComponents(string: processedUrl))
      }

      return url
    }

  }

}
