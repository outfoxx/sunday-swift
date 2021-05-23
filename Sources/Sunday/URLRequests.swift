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

  func with(httpMethod: HTTP.Method) -> URLRequest {
    var copy = self
    copy.httpMethod = httpMethod.rawValue
    return copy
  }

  func with(httpBody: Data?) -> URLRequest {
    var copy = self
    copy.httpBody = httpBody
    return copy
  }

  func with(httpBody: InputStream?) -> URLRequest {
    var copy = self
    copy.httpBodyStream = httpBody
    return copy
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
