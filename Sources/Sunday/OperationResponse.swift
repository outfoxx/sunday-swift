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

/// HTTP response headers with case-insensitive lookup.
public struct ResponseHeaders: Sendable {

  /// A single response header entry.
  public struct Entry: Sendable {

    /// Header field name.
    public let name: String

    /// Header field value.
    public let value: String

    /// Creates a response header entry.
    public init(name: String, value: String) {
      self.name = name
      self.value = value
    }

  }

  /// Header entries in the order supplied by the transport.
  public let entries: [Entry]

  /// Creates response headers from entries.
  public init(entries: [Entry]) {
    self.entries = entries
  }

  /// Creates response headers from an HTTP URL response.
  public init(response: HTTPURLResponse) {
    self.init(
      entries: response.allHeaderFields.flatMap { name, value in
        Self.entries(name: name, value: value)
      }
    )
  }

  /// Retrieves all values matching `name` case-insensitively.
  public func headers(named name: String) -> [String] {
    entries
      .filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
      .map(\.value)
  }

  /// Retrieves the first value matching `name` case-insensitively.
  public func header(named name: String) -> String? {
    entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  /// Parsed `Content-Type` header value.
  public var contentType: MediaType? {
    header(named: HTTP.StdHeaders.contentType).flatMap(MediaType.init)
  }

  private static func entries(name: AnyHashable, value: Any) -> [Entry] {
    let headerName = String(describing: name)
    return [Entry(name: headerName, value: String(describing: value))]
  }

}


/// A decoded operation result with HTTP response metadata.
public struct OperationResponse<Result: Sendable>: Sendable {

  /// Decoded operation result.
  public let result: Result

  /// HTTP status code.
  public let statusCode: Int

  /// HTTP response headers.
  public let headers: ResponseHeaders

  /// Creates an operation response.
  public init(result: Result, statusCode: Int, headers: ResponseHeaders) {
    self.result = result
    self.statusCode = statusCode
    self.headers = headers
  }

  /// Creates an operation response from an HTTP URL response.
  public init(result: Result, response: HTTPURLResponse) {
    self.init(result: result, statusCode: response.statusCode, headers: ResponseHeaders(response: response))
  }

  /// Retrieves all header values matching `name` case-insensitively.
  public func headers(named name: String) -> [String] {
    headers.headers(named: name)
  }

  /// Retrieves the first header value matching `name` case-insensitively.
  public func header(named name: String) -> String? {
    headers.header(named: name)
  }

  /// Parsed `Content-Type` header value.
  public var contentType: MediaType? {
    headers.contentType
  }

}
