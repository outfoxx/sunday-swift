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

import Foundation
import PotentCodables
import OSLog
import Synchronization

private struct RegisteredProblem: Sendable {

  let decode: @Sendable (MediaTypeDecoder, Data) throws -> any Problem

  static func erase<P: Problem>(_ problemType: P.Type) -> RegisteredProblem {
    RegisteredProblem(
      decode: { decoder, data in try decoder.decode(P.self, from: data) }
    )
  }

}


private struct URLSessionTransportState: Sendable {

  var isClosed = false
  var eventSources: [UUID: EventSource] = [:]

}


// swiftlint:disable type_body_length function_parameter_count
/// URLSession-backed transport shared by generated clients.
public final class URLSessionTransport: Transport, Sendable {

  public static let eventRequestTimeoutInterval: TimeInterval = 15 * 60 // 15 minutes

  public let baseURL: URI.Template
  public let session: URLSession
  public let eventSession: URLSession
  public let adapter: RequestAdapter?
  public let requestQueue: DispatchQueue
  public let mediaTypeEncoders: MediaTypeEncoders
  public let mediaTypeDecoders: MediaTypeDecoders
  public let pathEncoders: PathEncoders
  public let eventRequestTimeoutInterval: TimeInterval
  private let problemTypes = Mutex<[String: RegisteredProblem]>([:])
  private let state = Mutex(URLSessionTransportState())

  /// Creates a URLSession-backed transport.
  ///
  /// - Parameters:
  ///   - baseURL: Base URI template used to resolve request paths.
  ///   - session: Session used for non-streaming requests and responses.
  ///   - eventSession: Session used for server-sent event streams. Pass `session` when event streams
  ///     must use the same delegate or session behavior. Pass a session created with
  ///     `.sunday(configuration: .events(...))` or an equivalent configuration when SSE-specific
  ///     timeout and resource settings are required.
  ///   - adapter: Optional adapter applied to generated requests.
  ///   - requestQueue: Queue used to schedule request preparation work.
  ///   - mediaTypeEncoders: Encoders used to serialize request bodies.
  ///   - mediaTypeDecoders: Decoders used to deserialize response bodies.
  ///   - eventRequestTimeoutInterval: Timeout used for server-sent event requests.
  ///   - pathEncoders: Encoders used to format path parameter values.
  public init(
    baseURL: URI.Template,
    session: URLSession,
    eventSession: URLSession,
    adapter: RequestAdapter? = nil,
    requestQueue: DispatchQueue = .global(qos: .utility),
    mediaTypeEncoders: MediaTypeEncoders = .default,
    mediaTypeDecoders: MediaTypeDecoders = .default,
    eventRequestTimeoutInterval: TimeInterval = URLSessionTransport.eventRequestTimeoutInterval,
    pathEncoders: PathEncoders = .default
  ) {
    self.baseURL = baseURL
    self.session = session
    self.eventSession = eventSession
    self.adapter = adapter
    self.requestQueue = requestQueue
    self.mediaTypeEncoders = mediaTypeEncoders
    self.mediaTypeDecoders = mediaTypeDecoders
    self.pathEncoders = pathEncoders
    self.eventRequestTimeoutInterval = eventRequestTimeoutInterval
  }

  public convenience init(
    baseURL: URI.Template, adapter: RequestAdapter? = nil,
    serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
    sessionConfiguration: URLSessionConfiguration = .rest(),
    requestQueue: DispatchQueue = .global(qos: .utility),
    mediaTypeEncoders: MediaTypeEncoders = .default,
    mediaTypeDecoders: MediaTypeDecoders = .default
  ) {
    self.init(
      baseURL: baseURL,
      session: .sunday(configuration: sessionConfiguration, serverTrustPolicyManager: serverTrustPolicyManager),
      eventSession: .sunday(configuration: .events(), serverTrustPolicyManager: serverTrustPolicyManager),
      adapter: adapter,
      requestQueue: requestQueue,
      mediaTypeEncoders: mediaTypeEncoders,
      mediaTypeDecoders: mediaTypeDecoders
    )
  }

  deinit {
    closeEventSources()
    session.close(cancelOutstandingTasks: true)
    if eventSession !== session {
      eventSession.close(cancelOutstandingTasks: true)
    }
  }

  public func registerProblem<P: Problem>(type: URL, problemType: P.Type) {
    registerProblem(type: type.absoluteString, problemType: problemType)
  }

  public func registerProblem<P: Problem>(type: String, problemType: P.Type) {
    problemTypes.withLock { $0[type] = RegisteredProblem.erase(problemType) }
  }

  public func transportRequest<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) async throws -> URLRequest {

    var url =
      try baseURL.complete(
        relative: pathTemplate,
        parameters: try URI.Template.parameters(from: pathParameters ?? [:]),
        encoders: pathEncoders
      )

    // Encode & add query parameters to url
    if let queryParameters = queryParameters, !queryParameters.isEmpty {

      guard let urlQueryEncoder = try mediaTypeEncoders.find(for: .wwwFormUrlEncoded) as? WWWFormURLEncoder else {
        fatalError("MediaTypeEncoder for \(MediaType.wwwFormUrlEncoded) must be an instance of WWWFormURLEncoder")
      }

      var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
      urlComponents.percentEncodedQuery = try urlQueryEncoder.encodeQueryString(parameters: queryParameters)

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

    return try await adapter?.adapt(transport: self, urlRequest: urlRequest) ?? urlRequest
  }

  private func dataResponse(request: URLRequest) async throws -> (Data?, HTTPURLResponse) {

    return try await session.validatedData(for: request)
  }

  private func dataResponse<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) async throws -> (Data?, HTTPURLResponse) {

    let request = try await transportRequest(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    )

    return try await dataResponse(request: request)
  }

  public func transportResponse(request: URLRequest) async throws -> HTTPURLResponse {
    try await dataResponse(request: request).1
  }

  public func transportResponse<B: Encodable>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) async throws -> HTTPURLResponse {

    let request = try await transportRequest(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    )

    return try await transportResponse(request: request)
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

      return try mediaTypeDecoder.decode(D.self, from: data)

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
      return HTTP.StatusProblem(statusCode: response.statusCode)
    }

    // Ensure data is available
    guard let data = possibleData, !data.isEmpty else {
      // Return standard problem
      return HTTP.StatusProblem(statusCode: response.statusCode)
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
      let type = problemData["type"]?.stringValue,
      let registeredProblem = problemTypes.withLock({ $0[type] })
    else {
      // Return generic problem
      return GenericProblem(statusCode: response.statusCode, data: problemData)
    }

    // Parse registered problem type
    do {
      return try registeredProblem.decode(mediaTypeDecoder, data)
    }
    catch {
      return SundayError.responseDecodingFailed(reason: .deserializationFailed(contentType: .problem, error: error))
    }
  }

  public func response<B: Encodable, D: Decodable>(
    method: HTTP.Method,
    pathTemplate: String,
    pathParameters: Parameters?,
    queryParameters: Parameters?,
    body: B?,
    contentTypes: [MediaType]?,
    acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> OperationResponse<D> {

    do {

      let dataResponse = try await dataResponse(
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

      return OperationResponse(result: result, response: dataResponse.1)
    }
    catch {
      throw parse(error: error)
    }

  }

  public func response<B>(
    method: HTTP.Method,
    pathTemplate: String,
    pathParameters: Parameters?,
    queryParameters: Parameters?,
    body: B?,
    contentTypes: [MediaType]?,
    acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> OperationResponse<Void> where B: Encodable {

    do {

      let dataResponse = try await dataResponse(
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

      return OperationResponse(result: (), response: dataResponse.1)
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

      let dataResponse = try await dataResponse(
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

      let dataResponse = try await dataResponse(request: request)

      return try parse(dataResponse: dataResponse)

    }
    catch {
      throw parse(error: error)
    }
  }

  public func result(request: URLRequest) async throws {

    do {

      let dataResponse = try await dataResponse(request: request)

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

      let dataResponse = try await dataResponse(
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

  /// Creates a caller-owned event source for the generated request.
  ///
  /// The returned source is not retained by the transport. Callers are responsible for closing it.
  public func eventSource<B>(
    method: HTTP.Method, pathTemplate: String, pathParameters: Parameters? = nil, queryParameters: Parameters? = nil,
    body: B?, contentTypes: [MediaType]? = nil, acceptTypes: [MediaType]? = nil, headers: Parameters? = nil
  ) -> EventSource where B: Encodable & Sendable {

    eventSource(from: { @Sendable [weak self] in
      guard let self else { return nil }

      return try await self.transportRequest(
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

  /// Creates a caller-owned event source for a custom request builder.
  ///
  /// The returned source is not retained by the transport. Callers are responsible for closing it.
  public func eventSource(from request: @escaping @Sendable () async throws -> URLRequest?) -> EventSource {
    makeEventSource(from: request)
  }

  private func makeEventSource(from request: @escaping @Sendable () async throws -> URLRequest?) -> EventSource {
    EventSource(queue: requestQueue) { [weak self] headers in
      guard let self else { return nil }
      guard let request = try await request() else { return nil }
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
    decoder: @escaping @Sendable (TextMediaTypeDecoder, String?, String?, String, Logger) throws -> D?
  ) -> AsyncStream<D> where B: Encodable & Sendable {

    eventStream(
      decoder: decoder,
      from: { @Sendable [weak self] in
        guard let self else { return nil }

        return try await self.transportRequest(
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
    decoder: @escaping @Sendable (TextMediaTypeDecoder, String?, String?, String, Logger) throws -> D?,
    from request: @escaping @Sendable () async throws -> URLRequest?
  ) -> AsyncStream<D> {

    guard let jsonDecoder = try? mediaTypeDecoders.find(for: .json) as? TextMediaTypeDecoder else {
      fatalError("JSON media-type decoder must conform to TextMediaTypeDecoder")
    }

    return AsyncStream(D.self) { continuation in

      let eventSource = makeEventSource(from: request)
      guard let registration = register(eventSource: eventSource) else {
        continuation.finish()
        return
      }
      let setup = URLSessionTransportEventStreamSetup()

      continuation.onTermination = { @Sendable [weak self] _ in
        setup.terminate()?.cancel()

        Task {
          await eventSource.close()
          await eventSource.setOnMessage(nil)
          await eventSource.setOnError(nil)
          await eventSource.setOnStateError(nil)
          self?.unregister(registration: registration)
        }
      }

      let setupTask = setup.start(
        eventSource: eventSource,
        continuation: continuation,
        shouldCancel: { [weak self] in self?.isClosed ?? true },
        jsonDecoder: jsonDecoder,
        decoder: decoder
      )
      setup.store(task: setupTask)
    }
  }

  public func close(cancelOutstandingRequests: Bool = true) {
    closeEventSources()
    session.close(cancelOutstandingTasks: cancelOutstandingRequests)
    if eventSession !== session {
      eventSession.close(cancelOutstandingTasks: cancelOutstandingRequests)
    }
  }

  private func register(eventSource: EventSource) -> UUID? {
    state.withLock { state in
      guard !state.isClosed else {
        return nil
      }

      let registration = UUID()
      state.eventSources[registration] = eventSource
      return registration
    }
  }

  private func unregister(registration: UUID) {
    _ = state.withLock { state in
      state.eventSources.removeValue(forKey: registration)
    }
  }

  private func closeEventSources() {
    let currentEventSources = state.withLock { state in
      state.isClosed = true
      let currentEventSources = Array(state.eventSources.values)
      state.eventSources.removeAll()
      return currentEventSources
    }
    currentEventSources.forEach { eventSource in
      Task { await eventSource.close() }
    }
  }

  private var isClosed: Bool {
    state.withLock { $0.isClosed }
  }

}
// swiftlint:enable type_body_length function_parameter_count
