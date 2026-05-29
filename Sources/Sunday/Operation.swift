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


/// Describes a generated HTTP operation request.
public struct OperationSpec<RequestBody: Sendable>: Sendable {

  /// The HTTP method to use.
  public let method: HTTP.Method

  /// The URI template path relative to the transport base URL.
  public let pathTemplate: String

  /// Values used to expand `pathTemplate`.
  public let pathParameters: Parameters?

  /// Query parameter values for the operation.
  public let queryParameters: Parameters?

  /// Request body value.
  public let body: RequestBody?

  /// Candidate media types for encoding `body`.
  public let contentTypes: [MediaType]?

  /// Candidate media types accepted by the operation.
  public let acceptTypes: [MediaType]?

  /// HTTP header parameter values for the operation.
  public let headers: Parameters?

  private let prepareRequestBody: @Sendable (
    RequestBody?,
    [MediaType]?,
    MediaTypeEncoders
  ) throws -> PreparedRequestBody?

  /// Creates an operation request specification.
  public init(
    method: HTTP.Method,
    pathTemplate: String,
    pathParameters: Parameters? = nil,
    queryParameters: Parameters? = nil,
    body: RequestBody? = nil,
    contentTypes: [MediaType]? = nil,
    acceptTypes: [MediaType]? = nil,
    headers: Parameters? = nil,
    prepareBody: @escaping @Sendable (
      RequestBody?,
      [MediaType]?,
      MediaTypeEncoders
    ) throws -> PreparedRequestBody?
  ) {
    self.method = method
    self.pathTemplate = pathTemplate
    self.pathParameters = pathParameters
    self.queryParameters = queryParameters
    self.body = body
    self.contentTypes = contentTypes
    self.acceptTypes = acceptTypes
    self.headers = headers
    self.prepareRequestBody = prepareBody
  }

  func prepareBody(mediaTypeEncoders: MediaTypeEncoders) throws -> PreparedRequestBody? {
    try prepareRequestBody(body, contentTypes, mediaTypeEncoders)
  }

}


public extension OperationSpec where RequestBody: Encodable {

  /// Creates an operation request specification with an encodable request body.
  init(
    method: HTTP.Method,
    pathTemplate: String,
    pathParameters: Parameters? = nil,
    queryParameters: Parameters? = nil,
    body: RequestBody? = nil,
    contentTypes: [MediaType]? = nil,
    acceptTypes: [MediaType]? = nil,
    headers: Parameters? = nil
  ) {
    self.init(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    ) { body, contentTypes, mediaTypeEncoders in
      guard let body else {
        return nil
      }
      guard let contentType = contentTypes?.first(where: { mediaTypeEncoders.supports(for: $0) }) else {
        throw SundayError.requestEncodingFailed(reason: .noSupportedContentTypes(contentTypes ?? []))
      }
      let data = try mediaTypeEncoders.find(for: contentType).encode(body)
      return .data(data, contentType: contentType)
    }
  }

}


public extension OperationSpec where RequestBody == StreamingBody {

  /// Creates an operation request specification with a streaming request body.
  static func streaming(
    method: HTTP.Method,
    pathTemplate: String,
    pathParameters: Parameters? = nil,
    queryParameters: Parameters? = nil,
    body: StreamingBody? = nil,
    contentTypes: [MediaType]? = nil,
    acceptTypes: [MediaType]? = nil,
    headers: Parameters? = nil
  ) -> OperationSpec<StreamingBody> {
    OperationSpec<StreamingBody>(
      method: method,
      pathTemplate: pathTemplate,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      body: body,
      contentTypes: contentTypes,
      acceptTypes: acceptTypes,
      headers: headers
    ) { body, contentTypes, _ in
      guard let body else {
        return nil
      }
      return .stream(body, contentType: contentTypes?.first)
    }
  }

}


/// Describes problems that should be translated into a nil response value.
public struct NilifySpec: Sendable {

  /// HTTP statuses to translate into nil.
  public let statuses: [Int]

  /// Problem types to translate into nil.
  public let problemTypes: [any Problem.Type]

  /// Creates a nilify specification.
  public init(
    statuses: [Int] = [404],
    problemTypes: [any Problem.Type] = []
  ) {
    self.statuses = statuses
    self.problemTypes = problemTypes
  }

}


/// A generated operation that can be executed or converted into a native transport request.
public struct Operation<RequestBody: Sendable, ResponseBody: Sendable, TransportType: Transport>: Sendable {

  /// The generated operation request specification.
  public let spec: OperationSpec<RequestBody>

  private let transport: TransportType

  /// Creates an operation bound to a transport.
  public init(
    transport: TransportType,
    spec: OperationSpec<RequestBody>
  ) {
    self.transport = transport
    self.spec = spec
  }

  /// Builds a native transport request without executing it.
  public func transportRequest() async throws -> TransportType.Request {
    try await transport.transportRequest(spec: spec)
  }

  /// Executes the operation and returns the native transport response.
  public func transportResponse() async throws -> TransportType.Response {
    try await transport.transportResponse(spec: spec)
  }

}


/// An operation whose request body is streamed by the transport.
public typealias StreamingOperation<ResponseBody: Sendable, TransportType: Transport> =
  Operation<StreamingBody, ResponseBody, TransportType>


/// A generated operation that can execute select problems as nil responses.
public struct NilableOperation<
  RequestBody: Sendable,
  ResponseBody: Sendable,
  TransportType: Transport
>: Sendable {

  /// The generated operation request specification.
  public var spec: OperationSpec<RequestBody> {
    operation.spec
  }

  /// Problems translated into nil by `executeOrNil()`.
  public let nilify: NilifySpec

  private let operation: Operation<RequestBody, ResponseBody, TransportType>

  /// Creates a nilable operation bound to a transport.
  public init(
    transport: TransportType,
    spec: OperationSpec<RequestBody>,
    nilify: NilifySpec
  ) {
    self.operation = Operation(transport: transport, spec: spec)
    self.nilify = nilify
  }

  /// Builds a native transport request without executing it.
  public func transportRequest() async throws -> TransportType.Request {
    try await operation.transportRequest()
  }

  /// Executes the operation and returns the native transport response.
  public func transportResponse() async throws -> TransportType.Response {
    try await operation.transportResponse()
  }

}


extension Operation where ResponseBody: Decodable {

  /// Executes the operation and decodes the response value.
  public func execute() async throws -> ResponseBody {
    try await transport.result(spec: spec)
  }

  /// Executes the operation and returns the decoded value with the HTTP response.
  public func response() async throws -> OperationResponse<ResponseBody> {
    try await transport.response(spec: spec)
  }

}


extension NilableOperation where ResponseBody: Decodable {

  /// Executes the operation and decodes the response value.
  public func execute() async throws -> ResponseBody {
    try await operation.execute()
  }

  /// Executes the operation and translates configured problems into nil.
  public func executeOrNil() async throws -> ResponseBody? {
    try await nilifyResponse(statuses: nilify.statuses, problemTypes: nilify.problemTypes) {
      try await operation.execute()
    }
  }

  /// Executes the operation and returns the decoded value with the HTTP response.
  ///
  /// This returns the raw response path and does not apply `nilify`.
  /// Use `executeOrNil()` when configured statuses or problem types should be
  /// translated into `nil`.
  public func response() async throws -> OperationResponse<ResponseBody> {
    try await operation.response()
  }

  /// Executes the operation and translates configured problems into nil responses.
  public func responseOrNil() async throws -> OperationResponse<ResponseBody>? {
    try await nilifyResponse(statuses: nilify.statuses, problemTypes: nilify.problemTypes) {
      try await operation.response()
    }
  }

}


extension Operation where ResponseBody == Void {

  /// Executes the operation and decodes the response value.
  public func execute() async throws {
    try await transport.result(spec: spec)
  }

  /// Executes the operation and returns the decoded value with the HTTP response.
  public func response() async throws -> OperationResponse<Void> {
    try await transport.response(spec: spec)
  }

}


extension NilableOperation where ResponseBody == Void {

  /// Executes the operation and decodes the response value.
  public func execute() async throws {
    try await operation.execute()
  }

  /// Executes the operation and translates configured problems into nil.
  public func executeOrNil() async throws -> Void? {
    try await nilifyResponse(statuses: nilify.statuses, problemTypes: nilify.problemTypes) {
      try await operation.execute()
    }
  }

  /// Executes the operation and returns the decoded value with the HTTP response.
  ///
  /// This returns the raw response path and does not apply `nilify`.
  /// Use `executeOrNil()` when configured statuses or problem types should be
  /// translated into `nil`.
  public func response() async throws -> OperationResponse<Void> {
    try await operation.response()
  }

  /// Executes the operation and translates configured problems into nil responses.
  public func responseOrNil() async throws -> OperationResponse<Void>? {
    try await nilifyResponse(statuses: nilify.statuses, problemTypes: nilify.problemTypes) {
      try await operation.response()
    }
  }

}
