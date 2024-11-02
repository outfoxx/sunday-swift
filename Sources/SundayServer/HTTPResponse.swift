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


public enum HTTPCookieOption {
  case domain(String)
  case expires(Date)
  case httpOnly(Bool)
  case maxAge(Int)
  case path(String)
  case secure(Bool)
  case discard(Bool)
  case sameSite(String)
}


public enum HTTPResponseState {
  case initial
  case headerSent
  case sendingBody
  case sendingChunks
  case complete
}


public protocol HTTPResponse: AnyObject {

  var server: HTTPServer { get }

  var state: HTTPResponseState { get }

  var properties: [String: Any] { get set }

  func header(forName: String) -> String?
  func headers(forName: String) -> [String]
  func setHeaders(_: [String], forName: String)
  func addHeader(_: String, forName: String)

  func setContentType(_: MediaType)
  func addCookie(_ value: String, forName: String)
  func addCookie(_ value: String, forName: String, options: HTTPCookieOption...)

  /// Starts a response allowing a complete or chunked body response..
  ///
  /// # Note:
  /// For a complete body response the headers must include a
  /// `Content-Length: <length>` and for chunked transfer a
  /// `Transfer-Encoding: chunked` header must be present.
  ///
  /// - Precondition: state == .initial
  /// - Postcondition: state == .sendingBody || state == .sendingChunks
  /// - Parameters:
  ///   - status: HTTP status code
  ///
  func start(status: HTTP.Response.Status)

  /// Starts a response for chunked body encoding
  ///
  /// # Note:
  /// For a complete body response the headers must include a
  /// `Content-Length: <length>` and for chunked transfer a
  /// `Transfer-Encoding: chunked` header must be present.
  ///
  /// - Precondition: state == .initial
  /// - Postcondition: state == .sendingBody || state == .sendingChunks
  /// - Parameters:
  ///   - status: HTTP status code
  ///   - headers: Additional HTTP headers to send in header
  ///
  func start(status: HTTP.Response.Status, headers: HTTP.Headers)

  /// Sends a chunk of response data
  ///
  /// - Precondition: state == .sendingBody
  /// - Postcondition: state == .sendingChunks
  /// - Parameters:
  ///   - chunk: Data of chunk
  ///
  func send(chunk: Data)

  /// Sends a complete response body
  ///
  /// - Precondition: state == .sendingBody
  /// - Postcondition: state == .complete
  ///
  func send(body: Data)

  /// Sends response body data
  ///
  /// - Precondition: state == .sendingBody
  /// - Postcondition: state == .sendingBody || .complete
  ///
  func send(body: Data, final: Bool)

  /// Finishes a complete response body
  ///
  /// - Precondition: state == .sendingChunks
  /// - Parameters:
  ///   - trailers: Additional HTTP headers to send in trailer
  ///
  func finish(trailers: HTTP.Headers)

  func send(status: HTTP.Response.Status)
  func send(status: HTTP.Response.Status, body: Data)
  func send(status: HTTP.Response.Status, text: String)
  func send(status: HTTP.Response.Status, headers: [String: [String]], body: Data)
  func send<V>(status: HTTP.Response.Status, value: V) where V: Encodable
  func send<V>(status: HTTP.Response.Status, headers: [String: [String]], value: V) where V: Encodable

  func send(statusCode: HTTP.StatusCode)
  func send(statusCode: HTTP.StatusCode, body: Data)
  func send(statusCode: HTTP.StatusCode, text: String)
  func send(statusCode: HTTP.StatusCode, headers: [String: [String]], body: Data)
  func send<V>(statusCode: HTTP.StatusCode, value: V) where V: Encodable
  func send<V>(statusCode: HTTP.StatusCode, headers: [String: [String]], value: V) where V: Encodable

}


public extension HTTPResponse {

  func header(forName name: String) -> String? {
    return headers(forName: name).first
  }

  func addHeader(_ value: String, forName name: String) {
    setHeaders(headers(forName: name) + [value], forName: name)
  }

  func setContentType(_ contentType: MediaType) {
    setHeaders([contentType.value], forName: HTTP.StdHeaders.contentType)
  }

  func addCookie(_ value: String, forName name: String) {
    guard let cookie = HTTPCookie(properties: [.name: name, .value: value]) else {
      return
    }

    for header in HTTPCookie.requestHeaderFields(with: [cookie]) {
      addHeader(header.value, forName: header.key)
    }
  }

  func addCookie(_ value: String, forName name: String, options: HTTPCookieOption...) {
    let options = Dictionary(
      uniqueKeysWithValues: options
        .compactMap { option -> (HTTPCookiePropertyKey, Any)? in
          switch option {
          case .domain(let domain): return (.domain, domain)
          case .expires(let expires): return (.expires, expires)
          case .httpOnly: return nil
          case .maxAge(let maxAge): return (.maximumAge, maxAge)
          case .path(let path): return (.path, path)
          case .sameSite: return nil
          case .secure(let secure): return (.secure, secure)
          case .discard(let discard): return (.discard, discard)
          }
        } + [(.name, name), (.value, value)]
    )

    guard let cookie = HTTPCookie(properties: options) else {
      return
    }

    for header in HTTPCookie.requestHeaderFields(with: [cookie]) {
      addHeader(header.value, forName: header.key)
    }
  }

  func start(status: HTTP.Response.Status) {
    start(status: status, headers: [:])
  }

  func send(status: HTTP.Response.Status) {
    send(status: status, body: Data())
  }

  func send(status: HTTP.Response.Status, body: Data) {
    start(status: status, headers: [HTTP.StdHeaders.contentLength: [body.count.description]])
    send(body: body)
  }

  func send(status: HTTP.Response.Status, text: String) {
    start(status: status, headers: [HTTP.StdHeaders.contentType: [MediaType.plain.value]])
    send(body: text.data(using: .utf8) ?? Data())
  }

  func send(status: HTTP.Response.Status, headers: [String: [String]], body: Data) {
    start(status: status, headers: headers)
    send(body: body)
  }

  func send<V>(status: HTTP.Response.Status, value: V) where V: Encodable {
    send(status: status, headers: [:], value: value)
  }

  func send<V>(status: HTTP.Response.Status, headers: [String: [String]], value: V) where V: Encodable {
    send(status: .notAcceptable, text: "Encoding Response Failed - No Encoders")
  }

  func send(statusCode: HTTP.StatusCode) {
    send(status: .init(code: statusCode))
  }

  func send(statusCode: HTTP.StatusCode, body: Data) {
    send(status: .init(code: statusCode), body: body)
  }

  func send(statusCode: HTTP.StatusCode, text: String) {
    send(status: .init(code: statusCode), text: text)
  }

  func send(statusCode: HTTP.StatusCode, headers: [String: [String]], body: Data) {
    send(status: .init(code: statusCode), headers: headers, body: body)
  }

  func send<V>(statusCode: HTTP.StatusCode, value: V) where V: Encodable {
    send(status: .init(code: statusCode), value: value)
  }

  func send<V>(statusCode: HTTP.StatusCode, headers: [String: [String]], value: V) where V: Encodable {
    send(status: .init(code: statusCode), headers: headers, value: value)
  }

  /// Sends a chunk of response data, as the UTF8 encoded string.
  ///
  /// - Precondition: state == .sendingBody
  /// - Postcondition: state == .sendingChunks
  /// - Parameters:
  ///   - chunk: String of chunk
  ///   - as: Encoding for string
  ///
  func send(chunk: String) {
    return send(chunk: Data(chunk.utf8))
  }

}

public enum EncodingError: String, Error {
  case unableToEncodeString
}
