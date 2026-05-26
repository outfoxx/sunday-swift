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
import OSLog


// swiftlint:disable function_parameter_count
/// Builds and executes generated HTTP operations using a concrete transport implementation.
public protocol Transport: Sendable {

  /// Native request type created by this transport.
  associatedtype Request: Sendable = URLRequest

  /// Native response type produced by this transport.
  associatedtype Response: Sendable = HTTPURLResponse

  var baseURL: URI.Template { get }

  /// Registers a problem type for the given type URI.
  func registerProblem<P: Problem>(type: URL, problemType: P.Type)

  /// Registers a problem type for the given type URI.
  func registerProblem<P: Problem>(type: String, problemType: P.Type)

  /// Builds a native transport request without executing it.
  func transportRequest<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> Request

  /// Executes the operation request and returns the native transport response.
  func transportResponse<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> Response

  /// Executes a native transport request and returns the native transport response.
  func transportResponse(request: Request) async throws -> Response

  /// Executes the operation request and returns a decoded result with response metadata.
  func response<B: Encodable, D: Decodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> OperationResponse<D>

  /// Executes the operation request and returns a void result with response metadata.
  func response<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> OperationResponse<Void>

  /// Executes the operation request and returns only the decoded result.
  func result<B: Encodable, D: Decodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> D

  /// Executes the operation request and validates a void result.
  func result<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws

  /// Creates an event source for the operation request.
  func eventSource<B: Encodable & Sendable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) -> EventSource

  /// Creates an event stream for the operation request.
  func eventStream<B: Encodable & Sendable, D>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?,
    decoder: @escaping @Sendable (TextMediaTypeDecoder, String?, String?, String, Logger) throws -> D?
  ) -> AsyncStream<D>

  /// Closes any transport resources.
  func close(cancelOutstandingRequests: Bool)

}
// swiftlint:enable function_parameter_count
