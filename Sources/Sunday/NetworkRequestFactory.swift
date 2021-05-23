/*
 * Copyright 2021 Outfox, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

//  swiftlint:disable type_body_length function_parameter_count

import Combine
import Foundation
import PotentCodables


public class NetworkRequestFactory: RequestFactory {

  public let baseURL: URI.Template
  public let session: NetworkSession
  public let adapter: NetworkRequestAdapter?
  public let requestQueue: DispatchQueue
  public let mediaTypeEncoders: MediaTypeEncoders
  public let mediaTypeDecoders: MediaTypeDecoders
  private var problemTypes: [String: Problem.Type] = [:]

  public init(
    baseURL: URI.Template,
    session: NetworkSession,
    adapter: NetworkRequestAdapter? = nil,
    requestQueue: DispatchQueue = .global(qos: .utility),
    mediaTypeEncoders: MediaTypeEncoders = .default,
    mediaTypeDecoders: MediaTypeDecoders = .default
  ) {
    self.baseURL = baseURL
    self.session = session
    self.adapter = adapter
    self.requestQueue = requestQueue
    self.mediaTypeEncoders = mediaTypeEncoders
    self.mediaTypeDecoders = mediaTypeDecoders
  }

  public convenience init(
    baseURL: URI.Template, adapter: NetworkRequestAdapter? = nil,
    serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
    sessionConfiguration: URLSessionConfiguration = .rest(),
    requestQueue: DispatchQueue = .global(qos: .utility),
    mediaTypeEncoders: MediaTypeEncoders = .default,
    mediaTypeDecoders: MediaTypeDecoders = .default
  ) {
    self.init(
      baseURL: baseURL,
      session: .init(configuration: sessionConfiguration, serverTrustPolicyManager: serverTrustPolicyManager),
      adapter: adapter,
      requestQueue: requestQueue,
      mediaTypeEncoders: mediaTypeEncoders,
      mediaTypeDecoders: mediaTypeDecoders
    )
  }

  deinit {
    session.close(cancelOutstandingTasks: true)
  }

  public func with(sessionConfiguration: URLSessionConfiguration) -> NetworkRequestFactory {
    NetworkRequestFactory(
      baseURL: baseURL,
      adapter: adapter,
      serverTrustPolicyManager: session.serverTrustPolicyManager,
      sessionConfiguration: sessionConfiguration,
      requestQueue: requestQueue,
      mediaTypeEncoders: mediaTypeEncoders,
      mediaTypeDecoders: mediaTypeDecoders
    )
  }

  public func with(session: NetworkSession) -> NetworkRequestFactory {
    NetworkRequestFactory(
      baseURL: baseURL,
      session: session,
      adapter: adapter,
      requestQueue: requestQueue,
      mediaTypeEncoders: mediaTypeEncoders,
      mediaTypeDecoders: mediaTypeDecoders
    )
  }

  public func registerProblem(type: URL, problemType: Problem.Type) {
    registerProblem(type: type.absoluteString, problemType: problemType)
  }

  public func registerProblem(type: String, problemType: Problem.Type) {
    problemTypes[type] = problemType
  }

  public func request<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) -> RequestPublisher {

    Deferred { [self] () -> AnyPublisher<URLRequest, Error> in
      do {
        var url = try baseURL.complete(relative: pathTemplate, parameters: pathParameters ?? [:])

        // Encode & add query parameters to url
        if let queryParameters = queryParameters, !queryParameters.isEmpty {

          guard let urlQueryEncoder = try mediaTypeEncoders.find(for: .wwwFormUrlEncoded) as? WWWFormURLEncoder else {
            fatalError("MediaTypeEncoder for \(MediaType.wwwFormUrlEncoded) must be an instance of WWWFormURLEncoder")
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

        // Encode and add headers
        if let headers = headers {

          try HeaderParameters.encode(headers: headers)
            .forEach { entry in
              urlRequest.addValue(entry.value, forHTTPHeaderField: entry.name)
            }
        }

        // Determine & add accept header
        if let acceptTypes = acceptTypes {
          let supportedAcceptTypes = acceptTypes.filter { mediaTypeDecoders.supports(for: $0) }
          if supportedAcceptTypes.isEmpty {
            throw SundayError.requestEncodingFailed(reason: .noSupportedAcceptTypes(acceptTypes))
          }

          let accept = supportedAcceptTypes.map(\.value).joined(separator: " , ")

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
            throw SundayError.requestEncodingFailed(reason: .noSupportedContentTypes(contentTypes ?? []))
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
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) -> RequestResponsePublisher {

    return request(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    )
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

      // swiftlint:disable:next force_cast
      return Empty.instance as! D
    }

    guard let validData = data, !validData.isEmpty else {
      throw SundayError.responseDecodingFailed(reason: .noData)
    }

    guard
      let contentTypeName = response.value(forHttpHeaderField: HTTP.StdHeaders.contentType),
      let contentType = MediaType(contentTypeName)
    else {
      let badType = response.value(forHttpHeaderField: HTTP.StdHeaders.contentType) ?? "none"
      throw SundayError.responseDecodingFailed(reason: .invalidContentType(badType))
    }

    let mediaTypeDecoder = try mediaTypeDecoders.find(for: contentType)

    do {

      guard let value = try mediaTypeDecoder.decode(D.self, from: validData) as D? else {
        throw SundayError.responseDecodingFailed(reason: .missingValue)
      }

      return value

    }
    catch {
      throw SundayError.responseDecodingFailed(reason: .deserializationFailed(contentType: contentType, error: error))
    }
  }

  public func parse(error: Error) -> Error {

    // Check if this is an HTTP error response
    guard
      case SundayError.responseValidationFailed(reason: let reason) = error,
      case ResponseValidationFailureReason
      .unacceptableStatusCode(response: let response, data: let possibleData) = reason
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
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) -> RequestResultPublisher<D> {

    return response(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    )
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
      .tryMap { response, data in _ = try self.parse(response: response, data: data) as Empty }
      .mapError { self.parse(error: $0) }
      .eraseToAnyPublisher()
  }

  public func result<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?,
    body: B?, contentTypes: [MediaType]?, acceptTypes: [MediaType]?, headers: Parameters?
  ) -> RequestCompletePublisher {

    return response(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    )
    .tryMap { response, data in _ = try self.parse(response: response, data: data) as Empty }
    .mapError { self.parse(error: $0) }
    .eraseToAnyPublisher()
  }

  public func eventSource<B>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) -> EventSource where B: Encodable {

    eventSource(from: request(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    ))
  }

  public func eventSource(from requestPublisher: RequestPublisher) -> EventSource {

    return EventSource(queue: requestQueue) { headers in
      requestPublisher.flatMap { request in
        self.session.dataTaskStreamPublisher(for: request.adding(httpHeaders: headers))
      }
      .eraseToAnyPublisher()
    }
  }

  public func eventStream<B, D>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil,
    eventTypes: [String: AnyTextMediaTypeDecodable]
  ) -> RequestEventPublisher<D> where B: Encodable {

    eventStream(
      eventTypes: eventTypes,
      from: request(
        method: method,
        pathTemplate: pathTemplate,
        pathParameters: pathParameters,
        queryParameters: queryParameters,
        body: body,
        contentTypes: contentTypes,
        acceptTypes: acceptTypes,
        headers: headers
      )
    )
  }

  public func eventStream<D>(
    eventTypes: [String: AnyTextMediaTypeDecodable],
    from requestPublisher: RequestPublisher
  ) -> RequestEventPublisher<D> {
    Deferred { [self] () -> AnyPublisher<D, Error> in
      do {

        guard let jsonDecoder = try mediaTypeDecoders.find(for: .json) as? TextMediaTypeDecoder else {
          fatalError("JSON media-type decoder must conform to TextMediaTypeDecoder")
        }

        return EventPublisher<D>(eventTypes: eventTypes, decoder: jsonDecoder, queue: requestQueue) { headers in

          requestPublisher.flatMap { request in
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



public extension NetworkRequestFactory {

  func result<B: Encodable>(
    method: HTTP.Method,
    path: String,
    body: B? = nil,
    contentType: MediaType? = nil,
    acceptTypes: [MediaType]? = nil
  ) -> RequestCompletePublisher {
    return result(
      method: method,
      pathTemplate: path,
      pathParameters: nil,
      queryParameters: nil,
      body: body,
      contentTypes: contentType.flatMap { [$0] },
      acceptTypes: acceptTypes,
      headers: nil
    )
  }

  func result<B: Encodable, D: Decodable>(
    method: HTTP.Method,
    path: String,
    body: B? = nil,
    contentType: MediaType? = nil,
    acceptTypes: [MediaType]? = nil
  ) -> RequestResultPublisher<D> {
    return result(
      method: method,
      pathTemplate: path,
      pathParameters: nil,
      queryParameters: nil,
      body: body,
      contentTypes: contentType.flatMap { [$0] },
      acceptTypes: acceptTypes,
      headers: nil
    )
  }

}
