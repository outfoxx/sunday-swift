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

import Foundation
import PotentCodables
import OSLog


private let eventStreamLogger = Logger.for(category: "Event Streams")


public class NetworkRequestFactory: RequestFactory {

  public static let eventRequestTimeoutInterval: TimeInterval = 15 * 60 // 15 minutes

  public let baseURL: URI.Template
  public let session: NetworkSession
  public let eventSession: NetworkSession
  public let adapter: NetworkRequestAdapter?
  public let requestQueue: DispatchQueue
  public let mediaTypeEncoders: MediaTypeEncoders
  public let mediaTypeDecoders: MediaTypeDecoders
  public let pathEncoders: PathEncoders
  public let eventRequestTimeoutInterval: TimeInterval
  private var problemTypes: [String: Problem.Type] = [:]

  public init(
    baseURL: URI.Template,
    session: NetworkSession,
    eventSession: NetworkSession? = nil,
    adapter: NetworkRequestAdapter? = nil,
    requestQueue: DispatchQueue = .global(qos: .utility),
    mediaTypeEncoders: MediaTypeEncoders = .default,
    mediaTypeDecoders: MediaTypeDecoders = .default,
    eventRequestTimeoutInterval: TimeInterval = NetworkRequestFactory.eventRequestTimeoutInterval,
    pathEncoders: PathEncoders = .default
  ) {
    self.baseURL = baseURL
    self.session = session
    self.eventSession = eventSession ?? session.copy(configuration: .events())
    self.adapter = adapter
    self.requestQueue = requestQueue
    self.mediaTypeEncoders = mediaTypeEncoders
    self.mediaTypeDecoders = mediaTypeDecoders
    self.pathEncoders = pathEncoders
    self.eventRequestTimeoutInterval = eventRequestTimeoutInterval
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

  public func registerProblem(type: URL, problemType: Problem.Type) {
    registerProblem(type: type.absoluteString, problemType: problemType)
  }

  public func registerProblem(type: String, problemType: Problem.Type) {
    problemTypes[type] = problemType
  }

  public func request<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) async throws -> URLRequest {

    var url = try baseURL.complete(relative: pathTemplate, parameters: pathParameters ?? [:], encoders: pathEncoders)

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

    return try await adapter?.adapt(requestFactory: self, urlRequest: urlRequest) ?? urlRequest
  }

  public func response(request: URLRequest) async throws -> (Data?, HTTPURLResponse) {

    return try await session.validatedData(for: request)
  }

  public func response<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) async throws -> (Data?, HTTPURLResponse) {

    let request = try await request(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    )

    return try await session.validatedData(for: request)
  }

  public func parse<D: Decodable>(dataResponse: (Data?, HTTPURLResponse)) throws -> D {
    let (responseData, response) = dataResponse

    guard !emptyDataStatusCodes.contains(response.statusCode) else {

      guard D.self == Empty.self else {
        throw SundayError.unexpectedEmptyResponse
      }

      // swiftlint:disable:next force_cast
      return Empty.instance as! D
    }

    guard let data = responseData, !data.isEmpty else {
      throw SundayError.responseDecodingFailed(reason: .noData)
    }

    guard
      let contentTypeName = response.value(forHTTPHeaderField: HTTP.StdHeaders.contentType),
      let contentType = MediaType(contentTypeName)
    else {
      let badType = response.value(forHTTPHeaderField: HTTP.StdHeaders.contentType) ?? "none"
      throw SundayError.responseDecodingFailed(reason: .invalidContentType(badType))
    }

    let mediaTypeDecoder = try mediaTypeDecoders.find(for: contentType)

    do {

      guard let value = try mediaTypeDecoder.decode(D.self, from: data) as D? else {
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
      case let ResponseValidationFailureReason.unacceptableStatusCode(response: response, data: possibleData) = reason
    else {
      return error
    }

    // Check if response from error is "application/problem+json"
    guard
      let contentTypeHeader = response.value(forHTTPHeaderField: HTTP.StdHeaders.contentType),
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

  public func resultResponse<B: Encodable, D: Decodable>(
    method: HTTP.Method,
    pathTemplate: String,
    pathParameters: Parameters?,
    queryParameters: Parameters?,
    body: B?,
    contentTypes: [MediaType]?,
    acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> ResultResponse<D> {

    do {

      let dataResponse = try await response(
        method: method,
        pathTemplate: pathTemplate,
        pathParameters: pathParameters,
        queryParameters: queryParameters,
        body: body,
        contentTypes: contentTypes,
        acceptTypes: acceptTypes,
        headers: headers
      )

      let result = try parse(dataResponse: dataResponse) as D

      return ResultResponse(result: result, response: dataResponse.1)
    }
    catch {
      throw parse(error: error)
    }

  }

  public func resultResponse<B>(
    method: HTTP.Method,
    pathTemplate: String,
    pathParameters: Parameters?,
    queryParameters: Parameters?,
    body: B?,
    contentTypes: [MediaType]?,
    acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> ResultResponse<Void> where B: Encodable {

    do {

      let dataResponse = try await response(
        method: method,
        pathTemplate: pathTemplate,
        pathParameters: pathParameters,
        queryParameters: queryParameters,
        body: body,
        contentTypes: contentTypes,
        acceptTypes: acceptTypes,
        headers: headers
      )

      _ = try parse(dataResponse: dataResponse) as Empty

      return ResultResponse(result: (), response: dataResponse.1)
    }
    catch {
      throw parse(error: error)
    }

  }

  public func result<B: Encodable, D: Decodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) async throws -> D {

    do {

      let dataResponse = try await response(
        method: method,
        pathTemplate: pathTemplate,
        pathParameters: pathParameters,
        queryParameters: queryParameters,
        body: body,
        contentTypes: contentTypes,
        acceptTypes: acceptTypes,
        headers: headers
      )

      return try parse(dataResponse: dataResponse)

    }
    catch {
      throw parse(error: error)
    }
  }

  public func result<D: Decodable>(request: URLRequest) async throws -> D {

    do {

      let dataResponse = try await response(request: request)

      return try parse(dataResponse: dataResponse)

    }
    catch {
      throw parse(error: error)
    }
  }

  public func result(request: URLRequest) async throws {

    do {

      let dataResponse = try await response(request: request)

      _ = try parse(dataResponse: dataResponse) as Empty

    }
    catch {
      throw parse(error: error)
    }
  }

  public func result<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters?, queryParameters: Parameters?,
    body: B?, contentTypes: [MediaType]?, acceptTypes: [MediaType]?, headers: Parameters?
  ) async throws {

    do {

      let dataResponse = try await response(
        method: method,
        pathTemplate: pathTemplate,
        pathParameters: pathParameters,
        queryParameters: queryParameters,
        body: body,
        contentTypes: contentTypes,
        acceptTypes: acceptTypes,
        headers: headers
      )

      _ = try parse(dataResponse: dataResponse) as Empty

    }
    catch {
      throw parse(error: error)
    }
  }

  public func eventSource<B>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) -> EventSource where B: Encodable {

    eventSource(from: {
      if self.session.isClosed { return nil }
      return try await self.request(
        method: method,
        pathTemplate: pathTemplate,
        pathParameters: pathParameters,
        queryParameters: queryParameters,
        body: body,
        contentTypes: contentTypes,
        acceptTypes: acceptTypes,
        headers: headers
      )
    })
  }

  public func eventSource(from requestFactory: @escaping () async throws -> URLRequest?) -> EventSource {

    return EventSource(queue: requestQueue) { headers in
      guard let request = try await requestFactory() else { return nil }
      let updatedRequest =
        request
          .adding(httpHeaders: headers)
          .with(timeoutInterval: self.eventRequestTimeoutInterval)
      return try self.eventSession.dataEventStream(for: updatedRequest)
    }
  }

  public func eventStream<B, D>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil,
    decoder: @escaping (TextMediaTypeDecoder, String?, String?, String, Logger) throws -> D?
  ) -> AsyncStream<D> where B: Encodable {

    eventStream(
      decoder: decoder,
      from: {
        if self.session.isClosed { return nil }
        return try await self.request(
          method: method,
          pathTemplate: pathTemplate,
          pathParameters: pathParameters,
          queryParameters: queryParameters,
          body: body,
          contentTypes: contentTypes,
          acceptTypes: acceptTypes,
          headers: headers
        )
      }
    )
  }

  public func eventStream<D>(
    decoder: @escaping (TextMediaTypeDecoder, String?, String?, String, Logger) throws -> D?,
    from requestFactory: @escaping () async throws -> URLRequest?
  ) -> AsyncStream<D> {

    guard let jsonDecoder = try? mediaTypeDecoders.find(for: .json) as? TextMediaTypeDecoder else {
      fatalError("JSON media-type decoder must conform to TextMediaTypeDecoder")
    }

    return AsyncStream(D.self) { continuation in

      let eventSource = eventSource(from: requestFactory)

      continuation.onTermination = { @Sendable _ in  eventSource.close() }

      eventSource.onMessage = { event, id, data in

        // Ingore empty data events

        guard let data = data else {
          return
        }

        // Parse JSON and pass event on

        do {
          guard let event = try decoder(jsonDecoder, event, id, data, eventStreamLogger) else {
            return
          }

          continuation.yield(event)
        }
        catch {
          eventStreamLogger.error("Unable to decode event: \(error.localizedDescription, privacy: .public)")
          return
        }

      }

      eventSource.connect()
    }
  }

  public func close(cancelOutstandingRequests: Bool = true) {
    session.close(cancelOutstandingTasks: cancelOutstandingRequests)
    eventSession.close(cancelOutstandingTasks: cancelOutstandingRequests)
  }

}



public extension NetworkRequestFactory {

  func result<B: Encodable>(
    method: HTTP.Method,
    path: String,
    body: B? = nil,
    contentType: MediaType? = nil,
    acceptTypes: [MediaType]? = nil
  ) async throws {
    return try await result(
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
  ) async throws -> D {
    return try await result(
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
