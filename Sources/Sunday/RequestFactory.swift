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

//  swiftlint:disable function_parameter_count

import Foundation
import OSLog


public protocol RequestFactory {

  var baseURL: URI.Template { get }

  func registerProblem(type: URL, problemType: Problem.Type)
  func registerProblem(type: String, problemType: Problem.Type)

  func request<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> URLRequest

  func response<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> (Data?, HTTPURLResponse)

  func response(request: URLRequest) async throws -> (Data?, HTTPURLResponse)

  func resultResponse<B: Encodable, D: Decodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> ResultResponse<D>

  func resultResponse<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> ResultResponse<Void>

  func result<B: Encodable, D: Decodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws -> D

  func result<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) async throws

  func eventSource<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) -> EventSource

  func eventStream<B: Encodable, D>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?, decoder: @escaping (TextMediaTypeDecoder, String?, String?, String, Logger) throws -> D?
  ) -> AsyncStream<D>

  func close(cancelOutstandingRequests: Bool)

}
