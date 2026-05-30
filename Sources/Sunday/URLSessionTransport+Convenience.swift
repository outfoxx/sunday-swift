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


public extension URLSessionTransport {

  /// Executes a request with a literal path and validates a void result.
  func result<B: Encodable & Sendable>(
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

  /// Executes a request with a literal path and decodes a typed result.
  func result<B: Encodable & Sendable, D: Decodable>(
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
