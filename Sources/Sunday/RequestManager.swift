//
//  RequestManager.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


public protocol RequestManager {

  var baseURL: URLTemplate { get }

  func request<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                             pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                             contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                             headers: HTTP.Headers?) -> RequestPublisher

  func response(request: URLRequest) -> RequestResponsePublisher

  func response<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                              pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                              contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                              headers: HTTP.Headers?) -> RequestResponsePublisher

  func result<B: Encodable, D: Decodable>(method: HTTP.Method, pathTemplate: String,
                                          pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                          contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                          headers: HTTP.Headers?) -> RequestResultPublisher<D>

  func result<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                            pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                            contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                            headers: HTTP.Headers?) -> RequestCompletePublisher

  func events(from: RequestPublisher) -> EventSource

  func events<D: Decodable>(from: RequestPublisher) -> RequestEventPublisher<D>

}
