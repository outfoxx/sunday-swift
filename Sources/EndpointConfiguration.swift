//
//  EndpointConfiguration.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/12/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation
import Alamofire
import PotentCodables


public struct BaseURL {


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
    let template = relative.hasPrefix("/") ?  "\(self.template)\(relative)" : "\(self.template)/\(relative)"
    let url = try PathParameters.encode(template, with: parameters)

    guard let result = URL(string: url) else {
      throw SundayError.invalidURL
    }

    return result
  }

}


public struct EndpointConfiguration {

  public let baseURL: BaseURL

  public let defaultContentType: MediaType
  public let defaultAcceptTypes: [MediaType]

  public let defaultRequestQueue: DispatchQueue

  
  public init(baseURL: String, baseURLParameters: Parameters = [:],
              defaultContentType: MediaType = .json, defaultAcceptTypes: [MediaType] = [.json],
              defaultRequestQueue: DispatchQueue = .global(qos: .background)) {

    self.init(baseURL: BaseURL(template: baseURL, parameters: baseURLParameters),
              defaultContentType: defaultContentType, defaultAcceptTypes: defaultAcceptTypes,
              defaultRequestQueue: defaultRequestQueue)
    
  }

  public init(baseURL: BaseURL,
              defaultContentType: MediaType = .json, defaultAcceptTypes: [MediaType] = [.json],
              defaultRequestQueue: DispatchQueue = .global(qos: .background)) {
    self.baseURL = baseURL
    self.defaultContentType = defaultContentType
    self.defaultAcceptTypes = defaultAcceptTypes
    self.defaultRequestQueue = defaultRequestQueue
  }

}
