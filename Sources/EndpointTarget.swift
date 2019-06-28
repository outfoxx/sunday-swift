//
//  EndpointTarget.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/12/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation
import Alamofire


public struct EndpointTarget {

  public let baseURL: BaseURL
  
  public let defaultContentType: MediaType
  public let defaultAcceptTypes: [MediaType]
  
  public let defaultRequestQueue: DispatchQueue
  
  public let mediaTypeEncoders: MediaTypeEncoders
  public let mediaTypeDecoders: MediaTypeDecoders
  
  
  public init(baseURL: String, baseURLParameters: Parameters = [:],
              defaultContentType: MediaType = .json, defaultAcceptTypes: [MediaType] = [.json],
              defaultRequestQueue: DispatchQueue = .global(qos: .background),
              mediaTypeEncoders: MediaTypeEncoders = MediaTypeEncoders.default,
              mediaTypeDecoders: MediaTypeDecoders = MediaTypeDecoders.default) {
  
    self.init(baseURL: BaseURL(template: baseURL, parameters: baseURLParameters),
              defaultContentType: defaultContentType, defaultAcceptTypes: defaultAcceptTypes,
              defaultRequestQueue: defaultRequestQueue,
              mediaTypeEncoders: mediaTypeEncoders,
              mediaTypeDecoders: mediaTypeDecoders)
  }
  
  public init(baseURL: BaseURL,
              defaultContentType: MediaType = .json, defaultAcceptTypes: [MediaType] = [.json],
              defaultRequestQueue: DispatchQueue = .global(qos: .background),
              mediaTypeEncoders: MediaTypeEncoders = MediaTypeEncoders.default,
              mediaTypeDecoders: MediaTypeDecoders = MediaTypeDecoders.default) {
    self.baseURL = baseURL
    self.defaultContentType = defaultContentType
    self.defaultAcceptTypes = defaultAcceptTypes
    self.defaultRequestQueue = defaultRequestQueue
    self.mediaTypeEncoders = mediaTypeEncoders
    self.mediaTypeDecoders = mediaTypeDecoders
  }
  
}


public protocol RequestEncoder {
  func encode<T>(_ value: T) -> Data
}

public protocol RequestDecoder {
  func decode<T>(from: Data) -> T
}
