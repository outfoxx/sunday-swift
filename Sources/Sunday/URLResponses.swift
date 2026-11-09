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

public extension URLResponse {
  /// Copies the native response, preserving its concrete type and all Foundation metadata.
  /// Responses are immutable; Foundation may share storage with the original.
  func clone() -> Self {
    // NSCopying preserves the concrete type of Foundation responses.
    // swiftlint:disable:next force_cast
    copy() as! Self
  }
}

public extension HTTPURLResponse {
  /// Copies the public HTTP metadata with optional replacements. Omitted fields are preserved.
  /// Foundation does not expose the original HTTP protocol version for reconstruction.
  func clone(url: URL? = nil, statusCode: Int? = nil, headers: [String: String]? = nil) throws -> HTTPURLResponse {
    guard let url = url ?? self.url,
          let result = HTTPURLResponse(url: url, statusCode: statusCode ?? self.statusCode,
                                       httpVersion: nil, headerFields: headers ?? headerValues) else {
      throw URLError(.badServerResponse)
    }
    return result
  }

  /// Replaces a header case-insensitively. A nil value removes it.
  func setting(header name: String, value: String?) throws -> HTTPURLResponse {
    var fields = headerValues.filter { $0.key.caseInsensitiveCompare(name) != .orderedSame }
    fields[name] = value
    return try clone(headers: fields)
  }

  /// Appends to a comma-separated, list-valued header. Use `setting` for non-list headers.
  func adding(header name: String, value: String) throws -> HTTPURLResponse {
    let combined = self.value(forHTTPHeaderField: name).map { $0 + ", " + value } ?? value
    return try setting(header: name, value: combined)
  }

  /// Removes a header case-insensitively.
  func removing(header name: String) throws -> HTTPURLResponse { try setting(header: name, value: nil) }

  private var headerValues: [String: String] {
    allHeaderFields.reduce(into: [:]) { $0[String(describing: $1.key)] = String(describing: $1.value) }
  }
}
