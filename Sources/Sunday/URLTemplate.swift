//
//  URLTemplate.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public struct URLTemplate {


  public let template: String
  public let parameters: Parameters


  public init(template: String, parameters: Parameters = [:]) {
    self.template = template.hasSuffix("/") ? String(template.dropLast()) : template
    self.parameters = parameters
  }


  /// Builds a complete URL with the provided path arguments
  ///
  /// - Parameters:
  ///   - relative: Template for the relative portion of the complete URL
  ///   - parameters: Parameters for the template; these take precedence
  ///     when encountering duplicates
  public func complete(relative: String = "", parameters: Parameters = [:]) throws -> URL {

    let parameters = self.parameters.merging(parameters) { $1 }
    let template = relative.hasPrefix("/") ? "\(self.template)\(relative)" : "\(self.template)/\(relative)"
    let url = try PathParameters.encode(template, with: parameters)

    guard let result = URL(string: url) else {
      throw SundayError.invalidURL(URLComponents(string: url))
    }

    return result
  }

}
