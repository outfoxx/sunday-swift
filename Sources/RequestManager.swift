//
//  RequestManager.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/12/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Alamofire
import RxSwift


public protocol RequestManager {
  
  var target: EndpointTarget { get }

  func request<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                             pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                             contentType: MediaType?, acceptTypes: [MediaType]?, headers: HTTP.Headers?) throws -> DataRequest

  func fetch<B: Encodable, D: Decodable>(method: HTTP.Method, pathTemplate: String,
                                         pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                         contentType: MediaType?, acceptTypes: [MediaType]?, headers: HTTP.Headers?) throws -> Single<D>

  func fetch<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                           pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                           contentType: MediaType?, acceptTypes: [MediaType]?, headers: HTTP.Headers?) throws -> Completable

  func events(requestFactory: @escaping () throws -> DataRequest) -> EventSource

  func stream<D: Decodable>(requestFactory: @escaping () throws -> DataRequest) -> Observable<D>

}
