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


public extension URLRequest {

  /// Copies the entire native request, applies changes, and drops stale body replay metadata.
  /// Existing streams are shared, not read or duplicated. Use `replayingBody()` for a fresh stream,
  /// or `with(streamingBody:)` to install a replacement with its own replay factory.
  func clone(_ update: (inout URLRequest) throws -> Void = { _ in }) rethrows -> URLRequest {
    var result = self
    try update(&result)
    return result.removingObsoleteBodyReplay(comparedTo: self)
  }

  /// Replaces a header case-insensitively. A nil value removes it.
  func setting(header name: String, value: String?) -> URLRequest {
    clone { $0.setValue(value, forHTTPHeaderField: name) }
  }

  /// Appends a value to a list-valued header using Foundation's header semantics.
  func adding(header name: String, value: String) -> URLRequest {
    clone { $0.addValue(value, forHTTPHeaderField: name) }
  }

  /// Removes a header case-insensitively.
  func removing(header name: String) -> URLRequest { setting(header: name, value: nil) }

  func with(httpMethod: HTTP.Method) -> URLRequest {
    var copy = self
    copy.httpMethod = httpMethod.rawValue
    return copy
  }

  func with(httpBody: Data?) -> URLRequest {
    clone { $0.httpBody = httpBody }
  }

  func with(httpBody: InputStream?) -> URLRequest {
    clone { $0.httpBodyStream = httpBody }
  }

  func with(timeoutInterval: TimeInterval) -> URLRequest {
    var copy = self
    copy.timeoutInterval = timeoutInterval
    return copy
  }

  func adding(httpHeaders: HTTP.Headers) -> URLRequest {
    var copy = self
    for (headerName, headerValues) in httpHeaders {
      headerValues.forEach { copy.addValue($0, forHTTPHeaderField: headerName) }
    }
    return copy
  }

  func adding(httpHeaders: HTTP.HeaderList) -> URLRequest {
    var copy = self
    for httpHeader in httpHeaders {
      copy.addValue(httpHeader.value, forHTTPHeaderField: httpHeader.name)
    }
    return copy
  }

}

extension URLRequest {
  func removingObsoleteBodyReplay(comparedTo original: URLRequest) -> URLRequest {
    if let property = original.streamingBodyProperty, streamingBodyProperty === property,
       httpBodyStream !== original.httpBodyStream || httpBody != original.httpBody {
      return withoutStreamingBodyProperty()
    }
    return self
  }
}
