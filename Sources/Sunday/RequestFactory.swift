//
//  RequestFactory.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


public protocol RequestFactory {

  var baseURL: URI.Template { get }
  
  func with(sessionConfiguration: URLSessionConfiguration) -> RequestFactory
  
  func registerProblem(type: URL, problemType: Problem.Type)
  
  func request<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                             pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                             contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                             headers: HTTP.Headers?) -> RequestPublisher
  
  func response<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                              pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                              contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                              headers: HTTP.Headers?) -> RequestResponsePublisher

  func response(request: URLRequest) -> RequestResponsePublisher

  func result<B: Encodable, D: Decodable>(method: HTTP.Method, pathTemplate: String,
                                          pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                          contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                          headers: HTTP.Headers?) -> RequestResultPublisher<D>

  func result<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                            pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                            contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                            headers: HTTP.Headers?) -> RequestCompletePublisher

  func eventSource<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                                 pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                 contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                 headers: HTTP.Headers?) -> EventSource

  func eventStream<B: Encodable, D: Decodable>(method: HTTP.Method, pathTemplate: String,
                                               pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                               contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                               headers: HTTP.Headers?, eventTypes: [String: D.Type]) -> RequestEventPublisher<D>

  func close(cancelOutstandingRequests: Bool)

}
