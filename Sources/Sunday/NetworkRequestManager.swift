//
//  NetworkRequestManager.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


public class NetworkRequestManager: RequestManager {

  public let baseURL: URLTemplate
  public let session: URLSession
  public let adapter: NetworkRequestAdapter?
  public let requestQueue: DispatchQueue
  public let mediaTypeEncoders: MediaTypeEncoders
  public let mediaTypeDecoders: MediaTypeDecoders

  public init(baseURL: URLTemplate, adapter: NetworkRequestAdapter? = nil,
              serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
              sessionConfiguration: URLSessionConfiguration = .rest(),
              requestQueue: DispatchQueue = .global(qos: .utility),
              mediaTypeEncoders: MediaTypeEncoders = .default, mediaTypeDecoders: MediaTypeDecoders = .default) {
    self.baseURL = baseURL
    self.session = URLSession.create(configuration: sessionConfiguration,
                                     serverTrustPolicyManager: serverTrustPolicyManager)
    self.adapter = adapter
    self.requestQueue = requestQueue
    self.mediaTypeEncoders = mediaTypeEncoders
    self.mediaTypeDecoders = mediaTypeDecoders
  }
  
  deinit {
    session.invalidateAndCancel()
  }

  public func request<B: Encodable>(method: HTTP.Method, pathTemplate: String,
                                    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
                                    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                    headers: HTTP.Headers?) -> RequestPublisher {
    Deferred { [self] () -> AnyPublisher<URLRequest, Error> in
      do {
        var url = try baseURL.complete(relative: pathTemplate, parameters: pathParameters ?? [:])
        
        // Encode & add query parameters to url
        if let queryParameters = queryParameters, !queryParameters.isEmpty {
          guard let urlQueryEncoder = try mediaTypeEncoders.find(for: .wwwFormUrlEncoded) as? URLEncoder else {
            fatalError("MediaTypeEncoder for \(MediaType.wwwFormUrlEncoded) must be an instance of URLEncoder")
          }
          
          var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
          urlComponents.percentEncodedQuery = urlQueryEncoder.encodeQueryString(parameters: queryParameters)
          
          guard let queryUrl = urlComponents.url else {
            throw SundayError.invalidURL(urlComponents)
          }
          
          url = queryUrl
        }
        
        // Build basic request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        
        // Add headers
        headers?.forEach { key, values in
          values.forEach { value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
          }
        }
        
        // Determine & add accept header
        if let supportedAcceptTypes = acceptTypes?.filter({ mediaTypeDecoders.supports(for: $0) }), !supportedAcceptTypes.isEmpty {
          
          let accept = supportedAcceptTypes.map { $0.value }.joined(separator: " , ")
          
          urlRequest.setValue(accept, forHTTPHeaderField: HTTP.StdHeaders.accept)
        }
        
        // Encode & add body data
        if let body = body {
          
          // Determine content type
          guard let contentType = contentTypes?.first(where: { mediaTypeEncoders.supports(for: $0) }) else {
            throw SundayError.requestEncodingFailed(reason: .noSupportedContentType(contentTypes ?? []))
          }
          
          urlRequest.setValue(contentType.value, forHTTPHeaderField: HTTP.StdHeaders.contentType)
          urlRequest.httpBody = try mediaTypeEncoders.find(for: contentType).encode(body)
        }
        
        return adapter?.adapt(requestManager: self, urlRequest: urlRequest).eraseToAnyPublisher() ??
          Just(urlRequest).setFailureType(to: Error.self).eraseToAnyPublisher()
      }
      catch {
        return Fail(error: error).eraseToAnyPublisher()
      }
    }
    .eraseToAnyPublisher()
  }

  public func response(request: URLRequest) -> RequestResponsePublisher {

    return session.dataTaskValidatedPublisher(request: request).eraseToAnyPublisher()
  }

  public func response<B: Encodable>(method: HTTP.Method,
                                     pathTemplate: String, pathParameters: Parameters?,
                                     queryParameters: Parameters?,
                                     body: B?,
                                     contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                     headers: HTTP.Headers?) -> RequestResponsePublisher {
    return request(method: method, pathTemplate: pathTemplate, pathParameters: pathParameters,
                   queryParameters: queryParameters,
                   body: body,
                   contentTypes: contentTypes, acceptTypes: acceptTypes, headers: headers)
      .flatMap { request in
        return self.session.dataTaskValidatedPublisher(request: request)
      }
      .eraseToAnyPublisher()
  }

  public func parse<D: Decodable>(response: HTTPURLResponse, data: Data?) throws -> D {

    guard !emptyDataStatusCodes.contains(response.statusCode) else {
      guard D.self == Empty.self else {
        throw SundayError.unexpectedEmptyResponse
      }
      return Empty.instance as! D
    }

    guard let validData = data, !validData.isEmpty else {
      throw SundayError.responseDecodingFailed(reason: .inputDataNilOrZeroLength)
    }

    guard
      let contentTypeName = response.value(forHttpHeaderField: HTTP.StdHeaders.contentType),
      let contentType = MediaType(contentTypeName)
    else {
      let badType = response.value(forHttpHeaderField: HTTP.StdHeaders.contentType) ?? "none"
      throw SundayError.responseDecodingFailed(reason: .invalidContentType(badType))
    }

    let mediaTypeDecoder = try mediaTypeDecoders.find(for: contentType)

    guard let value = try mediaTypeDecoder.decode(D.self, from: validData) as D? else {
      throw SundayError.responseDecodingFailed(reason: .missingValue)
    }

    return value
  }

  public func parse(error: Error) -> Error {

    guard
      case SundayError.responseValidationFailed(reason: let reason) = error,
      case ResponseValidationFailureReason.unacceptableStatusCode(response: let response, data: let data) = reason,
      let contentTypeHeader = response.value(forHttpHeaderField: "Content-Type"),
      let contentType = MediaType(contentTypeHeader),
      contentType == .problem,
      let validData = data,
      let problem = try? mediaTypeDecoders.find(for: .problem).decode(Problem.self, from: validData)
    else {
      return error
    }

    return problem
  }

  public func result<D: Decodable>(request: URLRequest) -> RequestResultPublisher<D> {
    return response(request: request)
      .tryMap { try self.parse(response: $0.response, data: $0.data) }
      .mapError { self.parse(error: $0) }
      .eraseToAnyPublisher()
  }

  public func result<B: Encodable, D: Decodable>(method: HTTP.Method,
                                                 pathTemplate: String, pathParameters: Parameters?,
                                                 queryParameters: Parameters?,
                                                 body: B?,
                                                 contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                                 headers: HTTP.Headers?) -> RequestResultPublisher<D> {
    return response(method: method,
                    pathTemplate: pathTemplate, pathParameters: pathParameters,
                    queryParameters: queryParameters,
                    body: body,
                    contentTypes: contentTypes, acceptTypes: acceptTypes,
                    headers: headers)
      .tryMap { try self.parse(response: $0.response, data: $0.data) }
      .mapError { self.parse(error: $0) }
      .eraseToAnyPublisher()
  }

  public func result(request: URLRequest) -> RequestCompletePublisher {
    return response(request: request)
      .tryMap { (response, data) in try self.parse(response: response, data: data) as Empty }
      .mapError { self.parse(error: $0) }
      .ignoreOutput()
      .eraseToAnyPublisher()
  }

  public func result<B: Encodable>(method: HTTP.Method,
                                   pathTemplate: String, pathParameters: Parameters?,
                                   queryParameters: Parameters?,
                                   body: B?,
                                   contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
                                   headers: HTTP.Headers?) -> RequestCompletePublisher {
    return response(method: method,
                    pathTemplate: pathTemplate, pathParameters: pathParameters,
                    queryParameters: queryParameters,
                    body: body,
                    contentTypes: contentTypes, acceptTypes: acceptTypes,
                    headers: headers)
      .tryMap { (response, data) in try self.parse(response: response, data: data) as Empty }
      .mapError { self.parse(error: $0) }
      .ignoreOutput()
      .eraseToAnyPublisher()
  }

  public func events(from request$: RequestPublisher) -> EventSource {

    return EventSource(queue: requestQueue) { headers in
      request$.flatMap { request in
        self.session.dataTaskStreamPublisher(request: request.adding(httpHeaders: headers))
      }
      .eraseToAnyPublisher()
    }
  }

  public func events<D: Decodable>(from request$: RequestPublisher) -> RequestEventPublisher<D> {
    Deferred { [self] () -> AnyPublisher<D, Error> in
      do {
        
        let jsonDecoder = try mediaTypeDecoders.find(for: .json)
        
        return EventPublisher<D>(decoder: jsonDecoder, queue: requestQueue) { headers in
          
          request$.flatMap { request in
            self.session.dataTaskStreamPublisher(request: request.adding(httpHeaders: headers).with(timeoutInterval: 86400))
          }
          .eraseToAnyPublisher()
          
        }
        .eraseToAnyPublisher()
        
      }
      catch {
        return Fail(error: error).eraseToAnyPublisher()
      }
      
    }
    .eraseToAnyPublisher()
  }

  public func close(cancelOutstandingRequests: Bool = true) {
    if cancelOutstandingRequests {
      session.invalidateAndCancel()
    }
    else {
      session.finishTasksAndInvalidate()
    }
  }
  
}


private let acceptableStatusCodes: Set<Int> = [200, 201, 204, 205, 206, 400, 409, 410, 412, 413]



extension NetworkRequestManager {

  public func result<B: Encodable>(method: HTTP.Method, path: String, body: B? = nil,
                                   contentType: MediaType? = nil,
                                   acceptTypes: [MediaType]? = nil) -> RequestCompletePublisher {
    return result(method: method, pathTemplate: path, pathParameters: nil, queryParameters: nil, body: body,
                  contentTypes: contentType.flatMap { [$0] }, acceptTypes: acceptTypes, headers: nil)
  }

  public func result<B: Encodable, D: Decodable>(method: HTTP.Method, path: String, body: B? = nil,
                                                 contentType: MediaType? = nil,
                                                 acceptTypes: [MediaType]? = nil) -> RequestResultPublisher<D> {
    return result(method: method, pathTemplate: path, pathParameters: nil, queryParameters: nil, body: body,
                  contentTypes: contentType.flatMap { [$0] }, acceptTypes: acceptTypes, headers: nil)
  }

}
