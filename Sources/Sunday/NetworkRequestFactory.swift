//
//  NetworkRequestFactory.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine
import PotentCodables


public class NetworkRequestFactory: RequestFactory {

  public let baseURL: URI.Template
  public let session: NetworkSession
  public let adapter: NetworkRequestAdapter?
  public let requestQueue: DispatchQueue
  public let mediaTypeEncoders: MediaTypeEncoders
  public let mediaTypeDecoders: MediaTypeDecoders
  private var problemTypes: [String: Problem.Type] = [:]

  public init(baseURL: URI.Template, adapter: NetworkRequestAdapter? = nil,
              serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
              sessionConfiguration: URLSessionConfiguration = .rest(),
              requestQueue: DispatchQueue = .global(qos: .utility),
              mediaTypeEncoders: MediaTypeEncoders = .default, mediaTypeDecoders: MediaTypeDecoders = .default) {
    self.baseURL = baseURL
    self.session = NetworkSession(configuration: sessionConfiguration,
                                  serverTrustPolicyManager: serverTrustPolicyManager)
    self.adapter = adapter
    self.requestQueue = requestQueue
    self.mediaTypeEncoders = mediaTypeEncoders
    self.mediaTypeDecoders = mediaTypeDecoders
  }
  
  deinit {
    session.close(cancelOutstandingTasks: true)
  }
  
  public func with(sessionConfiguration: URLSessionConfiguration) -> RequestFactory {
    NetworkRequestFactory(baseURL: baseURL,
                          adapter: adapter,
                          serverTrustPolicyManager: session.serverTrustPolicyManager,
                          sessionConfiguration: sessionConfiguration,
                          requestQueue: requestQueue,
                          mediaTypeEncoders: mediaTypeEncoders,
                          mediaTypeDecoders: mediaTypeDecoders)
  }
  
  public func registerProblem(type: URL, problemType: Problem.Type) {
    self.problemTypes[type.absoluteString] = problemType
  }

  public func request<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?,
    body: B?, contentTypes: [MediaType]?, acceptTypes: [MediaType]?, headers: HTTP.Headers?
  ) -> RequestPublisher {
    
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
        
        // Determine content type
        let contentType = contentTypes?.first { mediaTypeEncoders.supports(for: $0) }
        
        // If matched, add content type (even if body is nil, to match any expected server requirements)
        if let contentType = contentType {
          urlRequest.setValue(contentType.value, forHTTPHeaderField: HTTP.StdHeaders.contentType)
        }

        // Encode & add body data
        if let body = body {
          guard let contentType = contentType else {
            throw SundayError.requestEncodingFailed(reason: .noSupportedContentType(contentTypes ?? []))
          }
          urlRequest.httpBody = try mediaTypeEncoders.find(for: contentType).encode(body)
        }
        
        return adapter?.adapt(requestFactory: self, urlRequest: urlRequest).eraseToAnyPublisher() ??
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

  public func response<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?,
    body: B?, contentTypes: [MediaType]?, acceptTypes: [MediaType]?, headers: HTTP.Headers?
  ) -> RequestResponsePublisher {
    
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

    // Check if this is an HTTP error response
    guard
      case SundayError.responseValidationFailed(reason: let reason) = error,
      case ResponseValidationFailureReason.unacceptableStatusCode(response: let response, data: let possibleData) = reason
    else {
      return error
    }

    // Check if response from error is "application/problem+json"
    guard
      let contentTypeHeader = response.value(forHttpHeaderField: HTTP.StdHeaders.contentType),
      let contentType = MediaType(contentTypeHeader),
      contentType == .problem
    else {
      return Problem(statusCode: response.statusCode)
    }
    
    // Ensure data is available
    guard let data = possibleData, !data.isEmpty else {
      // Return standard problem
      return Problem(statusCode: response.statusCode)
    }
    
    // Find decoder
    let mediaTypeDecoder: MediaTypeDecoder
    do {
      mediaTypeDecoder = try mediaTypeDecoders.find(for: .json)
    }
    catch {
      return error
    }
    
    // Parse data to dictionary
    var problemData: [String: AnyValue]
    do {
      problemData = try mediaTypeDecoder.decode([String: AnyValue].self, from: data)
    }
    catch {
      return SundayError.responseDecodingFailed(reason: .deserializationFailed(contentType: .problem, error: error))
    }
    
    // Find registered problem type
    guard
      let type = problemData.removeValue(forKey: "type")?.stringValue,
      let problemType = problemTypes[type]
    else {
      // Return generic problem
      return Problem(statusCode: response.statusCode, data: problemData)
    }
    
    // Parse registered problem type
    do {
      return try mediaTypeDecoder.decode(problemType, from: data)
    }
    catch {
      return SundayError.responseDecodingFailed(reason: .deserializationFailed(contentType: .problem, error: error))
    }
  }

  public func result<B: Encodable, D: Decodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?,
    body: B?, contentTypes: [MediaType]?, acceptTypes: [MediaType]?, headers: HTTP.Headers?
  ) -> RequestResultPublisher<D> {
    
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

  public func result<D: Decodable>(request: URLRequest) -> RequestResultPublisher<D> {
    return response(request: request)
      .tryMap { try self.parse(response: $0.response, data: $0.data) }
      .mapError { self.parse(error: $0) }
      .eraseToAnyPublisher()
  }

  public func result(request: URLRequest) -> RequestCompletePublisher {
    return response(request: request)
      .tryMap { (response, data) in _ = try self.parse(response: response, data: data) as Empty }
      .mapError { self.parse(error: $0) }
      .eraseToAnyPublisher()
  }

  public func result<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?,
    body: B?, contentTypes: [MediaType]?, acceptTypes: [MediaType]?, headers: HTTP.Headers?
  ) -> RequestCompletePublisher {
    
    return response(method: method,
                    pathTemplate: pathTemplate, pathParameters: pathParameters,
                    queryParameters: queryParameters,
                    body: body,
                    contentTypes: contentTypes, acceptTypes: acceptTypes,
                    headers: headers)
      .tryMap { (response, data) in _ = try self.parse(response: response, data: data) as Empty }
      .mapError { self.parse(error: $0) }
      .eraseToAnyPublisher()
  }

  public func eventSource<B>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?,
    body: B?, contentTypes: [MediaType]?, acceptTypes: [MediaType]?, headers: HTTP.Headers?
  ) -> EventSource where B : Encodable {
    
    self.eventSource(from: self.request(method: method,
                                        pathTemplate: pathTemplate,
                                        pathParameters: pathParameters,
                                        queryParameters: queryParameters,
                                        body: body,
                                        contentTypes: contentTypes,
                                        acceptTypes: acceptTypes,
                                        headers: headers))
  }

  public func eventSource(from request$: RequestPublisher) -> EventSource {

    return EventSource(queue: requestQueue) { headers in
      request$.flatMap { request in
        self.session.dataTaskStreamPublisher(for: request.adding(httpHeaders: headers))
      }
      .eraseToAnyPublisher()
    }
  }

  public func eventStream<B, D>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?,
    body: B?, contentTypes: [MediaType]?, acceptTypes: [MediaType]?, headers: HTTP.Headers?,
    eventTypes: [String : D.Type]
  ) -> RequestEventPublisher<D> where B : Encodable, D : Decodable {
    
    self.eventStream(eventTypes: eventTypes,
                     from: self.request(method: method,
                                        pathTemplate: pathTemplate,
                                        pathParameters: pathParameters,
                                        queryParameters: queryParameters,
                                        body: body,
                                        contentTypes: contentTypes,
                                        acceptTypes: acceptTypes,
                                        headers: headers))
  }

  public func eventStream<D: Decodable>(eventTypes: [String : D.Type], from request$: RequestPublisher) -> RequestEventPublisher<D> {
    Deferred { [self] () -> AnyPublisher<D, Error> in
      do {
        
        guard let jsonDecoder = try mediaTypeDecoders.find(for: .json) as? TextMediaTypeDecoder else {
          fatalError("JSON media-type decoder must conform to TextMediaTypeDecoder")
        }
        
        return EventPublisher<D>(eventTypes: eventTypes, decoder: jsonDecoder, queue: requestQueue) { headers in
          
          request$.flatMap { request in
            self.session.dataTaskStreamPublisher(for: request.adding(httpHeaders: headers).with(timeoutInterval: 86400))
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
    session.close(cancelOutstandingTasks: cancelOutstandingRequests)
  }
  
}



extension NetworkRequestFactory {

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
