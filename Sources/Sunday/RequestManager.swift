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
                             headers: HTTP.Headers?) throws -> AnyPublisher<URLRequest, Error>

  func response(request: URLRequest) -> AnyPublisher<(response: HTTPURLResponse, data: Data?), Error>

  func response<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                              pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                              contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                              headers: HTTP.Headers?) throws -> AnyPublisher<(response: HTTPURLResponse, data: Data?), Error>

  func result<B: Encodable, D: Decodable>(method: HTTP.Method, pathTemplate: String,
                                          pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                          contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                          headers: HTTP.Headers?) throws -> AnyPublisher<D, Error>

  func result<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                            pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                            contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                            headers: HTTP.Headers?) throws -> AnyPublisher<Never, Error>

  func events(from: AnyPublisher<URLRequest, Error>) -> EventSource

  func events<D: Decodable>(from: AnyPublisher<URLRequest, Error>) throws -> AnyPublisher<D, Error>

}
