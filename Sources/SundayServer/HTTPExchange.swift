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


public extension HTTP {

  struct Request {

    public let method: HTTP.Method
    public let url: URLComponents
    public let version: HTTP.Version
    public let headers: HTTP.Headers
    public let rawHeaders: HTTP.RawHeaders
    public let body: Data?

    public init(
      method: HTTP.Method,
      url: URL,
      version: HTTP.Version,
      headers: HTTP.Headers,
      rawHeaders: HTTP.RawHeaders,
      body: Data?
    ) {
      self.method = method
      self.url = URLComponents(url: url, resolvingAgainstBaseURL: true)!
      self.version = version
      self.headers = headers
      self.rawHeaders = rawHeaders
      self.body = body
    }

  }

  struct Response {

    public struct Status: CustomStringConvertible {
      public let code: Int
      public let info: String

      public init(code: Int, info: String) {
        self.code = code
        self.info = info
      }

      public init(code: StatusCode) {
        self.init(code: code.rawValue, info: HTTP.statusText[code]!.uppercased())
      }

      public var description: String {
        return "\(code) \(info)"
      }

      // 1XX

      public static let `continue` = Status(code: .continue)
      public static let switchingProtocols = Status(code: .switchingProtocols)

      // 2XX

      public static let ok = Status(code: .ok)
      public static let created = Status(code: .created)
      public static let accepted = Status(code: .accepted)
      public static let nonAuthoritativeInformation = Status(code: .nonAuthoritativeInformation)
      public static let noContent = Status(code: .noContent)
      public static let resetContent = Status(code: .resetContent)
      public static let partialContent = Status(code: .partialContent)

      // 3XX

      public static let multipleChoices = Status(code: .multipleChoices)
      public static let movedPermanently = Status(code: .movedPermanently)
      public static let found = Status(code: .found)
      public static let seeOther = Status(code: .seeOther)
      public static let notModified = Status(code: .notModified)
      public static let useProxy = Status(code: .useProxy)
      public static let temporaryRedirect = Status(code: .temporaryRedirect)

      // 4XX

      public static let badRequest = Status(code: .badRequest)
      public static let unauthenticated = Status(code: .unauthenticated)
      public static let paymentRequired = Status(code: .paymentRequired)
      public static let forbidden = Status(code: .forbidden)
      public static let notFound = Status(code: .notFound)
      public static let methodNotAllowed = Status(code: .methodNotAllowed)
      public static let notAcceptable = Status(code: .notAcceptable)
      public static let proxyAuthenticationRequired = Status(code: .proxyAuthenticationRequired)
      public static let requestTimeout = Status(code: .requestTimeout)
      public static let conflict = Status(code: .conflict)
      public static let gone = Status(code: .gone)
      public static let lengthRequired = Status(code: .lengthRequired)
      public static let preconditionFailed = Status(code: .preconditionFailed)
      public static let requestEntityTooLarge = Status(code: .requestEntityTooLarge)
      public static let requestUriTooLong = Status(code: .requestUriTooLong)
      public static let unsupportedMediaType = Status(code: .unsupportedMediaType)
      public static let requestRangeNotSatisfiable = Status(code: .requestRangeNotSatisfiable)
      public static let expectationFailed = Status(code: .expectationFailed)

      // 5XX

      public static let internalServerError = Status(code: .internalServerError)
      public static let notImplemented = Status(code: .notImplemented)
      public static let badGateway = Status(code: .badGateway)
      public static let serviceUnavailable = Status(code: .serviceUnavailable)
      public static let gatewayTimeout = Status(code: .gatewayTimeout)
      public static let httpVersionNotSupported = Status(code: .httpVersionNotSupported)

    }

    private init() {
      // disallow creation
    }

  }

}


extension HTTP.Request: CustomStringConvertible {

  public var description: String {
    var lines: [String] = []
    lines
      .append(
        "\(method.rawValue.uppercased()) \(url.url?.absoluteString ?? "/") HTTP/\(version.major).\(version.minor)"
      )
    for (header, values) in headers {
      for value in values {
        lines.append("\(header.lowercased().split(separator: "-").map(\.capitalized).joined(separator: "-")): \(value)")
      }
    }
    return lines.joined(separator: "\n")
  }

}
