//
//  NetworkRequestManager.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/12/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation
import Alamofire
import RxSwift


public struct NetworkRequestManager : RequestManager {


  public let target: EndpointTarget
  public let sessionManager: SessionManager


  public init(target: EndpointTarget, sessionManager: SessionManager = standard()) {
    self.target = target
    self.sessionManager = sessionManager
  }

  public static func standard(from config: URLSessionConfiguration = .default,
                              delegate: SessionDelegate = SessionDelegate(),
                              adaptedBy adapter: RequestAdapter? = nil,
                              retriedBy retrier: RequestRetrier? = nil,
                              trusting trustPolicies: [String: ServerTrustPolicy]? = nil,
                              requestTimeout: TimeInterval? = nil,
                              resourceTimeout: TimeInterval? = nil,
                              configurator: (URLSessionConfiguration) -> Void = { _ in }) -> SessionManager {
  
    config.networkServiceType = .default
    config.allowsCellularAccess = true
    config.httpShouldUsePipelining = true
    config.timeoutIntervalForRequest = requestTimeout ?? sessionTimeoutIntervalForRequestDefault
    config.timeoutIntervalForResource = resourceTimeout ?? sessionTimeoutIntervalForResourceDefault
  
    if #available(iOS 11, macOS 10.13, tvOS 11, *) {
      config.waitsForConnectivity = true
    }
  
    configurator(config)
  
    let sessionManager = SessionManager(configuration: config,
                                        delegate: delegate,
                                        serverTrustPolicyManager: trustPolicies.map { ServerTrustPolicyManager(policies: $0) })
    sessionManager.adapter = adapter
    sessionManager.retrier = retrier
    return sessionManager
  }

  public func request<B: Encodable>(method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                    contentType: MediaType?, acceptTypes: [MediaType]?, headers: HTTP.Headers?) throws -> DataRequest {

    let contentType = contentType ?? target.defaultContentType
    let acceptTypes = acceptTypes ?? target.defaultAcceptTypes

    // Determine accept header value (if needed)
    let accept = acceptTypes.map { $0.value }.joined(separator: " , ")
    let url = try target.baseURL.complete(relative: pathTemplate, parameters: pathParameters ?? [:])

    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.setValue(accept, forHTTPHeaderField: HTTP.StandardHeaders.accept)

    headers?.forEach { key, values in
      values.forEach { value in
        request.setValue(value, forHTTPHeaderField: key)
      }
    }

    if let queryParameters = queryParameters, !queryParameters.isEmpty {
      request = try URLEncoding.queryString.encode(request, with: queryParameters)
    }

    if let body = body {
      if request.value(forHTTPHeaderField: HTTP.StandardHeaders.contentType) == nil {
        request.setValue(contentType.value, forHTTPHeaderField: HTTP.StandardHeaders.contentType)
      }

      request.httpBody = try target.mediaTypeEncoders.find(for: contentType).encode(body)
    }

    return sessionManager.request(request).validate(statusCode: acceptableStatusCodes)
  }

  public func fetch<B: Encodable, D: Decodable>(method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                                contentType: MediaType?, acceptTypes: [MediaType]?, headers: HTTP.Headers?) throws -> Single<D> {

    return try self
      .request(method: method, pathTemplate: pathTemplate, pathParameters: pathParameters, queryParameters: queryParameters, body: body,
               contentType: contentType, acceptTypes: acceptTypes, headers: headers)
      .observe(mediaTypeDecoders: target.mediaTypeDecoders,
               queue: target.defaultRequestQueue)
  }

  public func fetch<B: Encodable>(method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                  contentType: MediaType?, acceptTypes: [MediaType]?, headers: HTTP.Headers?) throws -> Completable {

    return try self
      .request(method: method, pathTemplate: pathTemplate, pathParameters: pathParameters, queryParameters: queryParameters, body: body,
               contentType: contentType, acceptTypes: acceptTypes, headers: headers)
      .complete(mediaTypeDecoders: target.mediaTypeDecoders,
                queue: target.defaultRequestQueue)
  }

  public func events(requestFactory: @escaping () throws -> DataRequest) -> EventSource {

    return EventSource(queue: target.defaultRequestQueue, requestFactory: requestFactory)
  }

  public func stream<D: Decodable>(requestFactory: @escaping () throws -> DataRequest) -> Observable<D> {

    let jsonDecoder = try! target.mediaTypeDecoders.find(for: .json)

    return ObservableEventSource<D>(eventDecoder: jsonDecoder,
                                    queue: target.defaultRequestQueue,
                                    requestFactory: requestFactory).observe()
  }

}


private let acceptableStatusCodes: Set<Int> = [200, 201, 204, 205, 206, 400, 409, 410, 412, 413]

fileprivate let sessionTimeoutIntervalForResourceDefault = TimeInterval(60)
fileprivate let sessionTimeoutIntervalForRequestDefault = TimeInterval(15)



extension NetworkRequestManager {
  
  public func fetch<B: Encodable>(method: HTTP.Method, path: String, body: B? = nil) throws -> Completable {
    return try fetch(method: method, pathTemplate: path, pathParameters: nil, queryParameters: nil, body: body, contentType: nil, acceptTypes: nil, headers: nil)
  }
  
  public func fetch<B: Encodable, D: Decodable>(method: HTTP.Method, path: String, body: B? = nil) throws -> Single<D> {
    return try fetch(method: method, pathTemplate: path, pathParameters: nil, queryParameters: nil, body: body, contentType: nil, acceptTypes: nil, headers: nil)
  }

}
