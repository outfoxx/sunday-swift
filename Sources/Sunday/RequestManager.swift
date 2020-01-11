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
import RxSwift


public protocol RequestManager {

  var baseURL: URLTemplate { get }

  func request<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                             pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                             contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                             headers: HTTP.Headers?) throws -> Single<URLRequest>

  func response(request: URLRequest) -> Single<(response: HTTPURLResponse, data: Data?)>

  func response(request: URLRequest, options: URLSession.RequestOptions) -> Single<(response: HTTPURLResponse, data: Data?)>

  func response<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                              pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                              contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                              headers: HTTP.Headers?) throws -> Single<(response: HTTPURLResponse, data: Data?)>

  func result<B: Encodable, D: Decodable>(method: HTTP.Method, pathTemplate: String,
                                          pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                          contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                          headers: HTTP.Headers?) throws -> Single<D>

  func result<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                            pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                            contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                            headers: HTTP.Headers?) throws -> Completable

  func events(from: Single<URLRequest>) -> EventSource

  func events<D: Decodable>(from: Single<URLRequest>) throws -> Observable<D>

}
