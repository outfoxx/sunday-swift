//
//  URITemplate.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import URITemplate

public struct URI: Equatable, Hashable {

  public enum Error: Swift.Error {
    case invalidURI
  }
  
  private let components: URLComponents
  
  public var scheme: String { components.scheme! }
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
  
  public init(scheme: String, path: String, fragment: String? = nil) {
    var components = URLComponents()
    components.scheme = scheme
    components.path = path
    components.fragment = fragment
    self.init(components: components)
  }
  
  public init(components: URLComponents) {
    self.components = components
  }

  public struct Template : ExpressibleByStringLiteral {
    
    public enum Error: Swift.Error {
      case missingParameterValue(name: String)
      case unsupportedParameterType(name: String, type: Any.Type)
    }
    
    private static var implCache = [String: URITemplate]()
    private static let lock = NSRecursiveLock()
    
    public let template: String
    public let parameters: Parameters
    
    public init(template: String, parameters: Parameters = [:]) {
      self.template = template.hasSuffix("/") ? String(template.dropLast()) : template
      self.parameters = parameters
    }
    
    public init(stringLiteral template: String) {
      self.init(template: template)
    }    
    
    /// Builds a complete URL with the provided path arguments
    ///
    /// - Parameters:
    ///   - relative: Template for the relative portion of the complete URL
    ///   - parameters: Parameters for the template; these take precedence
    ///     when encountering duplicates
    public func complete(relative: String = "", parameters: Parameters = [:]) throws -> URL {
      
      let full: String
      if relative == "" {
        full = template
      } else if template.hasSuffix("/") && relative.hasPrefix("/")  {
        full = "\(template)\(relative.dropFirst())"
      }
      else if template.hasSuffix("/") || relative.hasPrefix("/") {
        full = "\(template)\(relative)"
      }
      else {
        full = "\(template)/\(relative)"
      }
      
      let impl = try Self.impl(for: full)
      let parameters = self.parameters.merging(parameters) { $1 }
      var variables = [String: VariableValue]()
      
      for variableName in impl.variableNames {
        
        switch parameters[variableName] {
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

extension URI: Codable {
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(string: container.decode(String.self))
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(components.string!)
  }
  
}
