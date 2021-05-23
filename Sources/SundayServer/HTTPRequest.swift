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
import Sunday


public protocol HTTPRequest: AnyObject {

  var server: HTTPServer { get }

  var raw: HTTP.Request { get }

  var method: HTTP.Method { get }

  var url: URLComponents { get }

  var headers: HTTP.Headers { get }
  func headers(for: String) -> [String]
  func header(for: String) -> String?

  var body: Data? { get }

  func accepts(_ contentType: MediaType) -> Bool

}


public extension HTTPRequest {

  var method: HTTP.Method { raw.method }

  var url: URLComponents { raw.url }

  var headers: HTTP.Headers { raw.headers }

  func headers(for name: String) -> [String] {
    return raw.headers.first { name.caseInsensitiveCompare($0.key) == .orderedSame }?.value ?? []
  }

  func header(for name: String) -> String? { headers(for: name).first }

  var body: Data? { raw.body }

  func accepts(_ contentType: MediaType) -> Bool {
    let accepts = headers(for: HTTP.StdHeaders.accept)
    guard accepts.isEmpty else { return true }
    for accept in accepts {
      guard let acceptType = MediaType(accept) else { continue }
      if MediaType.compatible(lhs: acceptType, rhs: contentType) {
        return true
      }
    }
    return false
  }

}
