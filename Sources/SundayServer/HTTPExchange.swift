//
//  HTTPExchange.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import RxSwift
import Sunday


public extension HTTP {

  struct Request {

    public let method: HTTP.Method
    public let url: URLComponents
    public let version: HTTP.Version
    public let headers: HTTP.Headers
    public let rawHeaders: HTTP.RawHeaders
    public let body: Data?

    public init(method: HTTP.Method, url: URL, version: HTTP.Version,
                headers: HTTP.Headers, rawHeaders: HTTP.RawHeaders,
                body: Data?) {
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
      public let code: StatusCode
      public let info: String

      public init(code: StatusCode, info: String) {
        self.code = code
        self.info = info
      }

      public var description: String {
        return "\(code.rawValue) \(info)"
      }

      // 1XX

      public static let `continue` = Status(code: .continue, info: "CONTINUE")
      public static let switchingProtocols = Status(code: .switchingProtocols, info: "SWITCHING PROTOCOLS")

      // 2XX

      public static let ok = Status(code: .ok, info: "OK")
      public static let created = Status(code: .created, info: "CREATED")
      public static let accepted = Status(code: .accepted, info: "ACCEPTED")
      public static let nonAuthoritativeInformation = Status(code: .nonAuthoritativeInformation, info: "NON-AUTHORITATIVE INFORMATION")
      public static let noContent = Status(code: .noContent, info: "NO CONTENT")
      public static let resetContent = Status(code: .resetContent, info: "RESET CONTENT")
      public static let partialContent = Status(code: .partialContent, info: "PARTIAL CONTENT")

      // 3XX

      public static let multipleChoices = Status(code: .multipleChoices, info: "MULTIPLE CHOICES")
      public static let movedPermanently = Status(code: .movedPermanently, info: "MOVED PERMANENTLY")
      public static let found = Status(code: .found, info: "FOUND")
      public static let seeOther = Status(code: .seeOther, info: "SEE OTHER")
      public static let notModified = Status(code: .notModified, info: "NOT MODIFIED")
      public static let useProxy = Status(code: .useProxy, info: "USE PROXY")
      public static let temporaryRedirect = Status(code: .temporaryRedirect, info: "TEMPORARY REDIRECT")

      // 4XX

      public static let badRequest = Status(code: .badRequest, info: "BAD REQUEST")
      public static let unauthenticated = Status(code: .unauthenticated, info: "UNAUTHENTICATED")
      public static let paymentRequired = Status(code: .paymentRequired, info: "PAYMENT REQUIRED")
      public static let forbidden = Status(code: .forbidden, info: "FORBIDDEN")
      public static let notFound = Status(code: .notFound, info: "NOT FOUND")
      public static let methodNotAllowed = Status(code: .methodNotAllowed, info: "METHOD NOT ALLOWED")
      public static let notAcceptable = Status(code: .notAcceptable, info: "NOT ACCEPTABLE")
      public static let proxyAuthenticationRequired = Status(code: .proxyAuthenticationRequired, info: "PROXY AUTHENTICATION REQUIRED")
      public static let requestTimeout = Status(code: .requestTimeout, info: "REQUEST TIMEOUT")
      public static let conflict = Status(code: .conflict, info: "CONFLICT")
      public static let gone = Status(code: .gone, info: "GONE")
      public static let lengthRequired = Status(code: .lengthRequired, info: "LENGTH REQUIRED")
      public static let preconditionFailed = Status(code: .preconditionFailed, info: "PRECONDITION FAILED")
      public static let requestEntityTooLarge = Status(code: .requestEntityTooLarge, info: "REQUEST ENTITY TOO LARGE")
      public static let requestUriTooLong = Status(code: .requestUriTooLong, info: "REQUEST URI TOO LONG")
      public static let unsupportedMediaType = Status(code: .unsupportedMediaType, info: "UNSUPPORTED MEDIA TYPE")
      public static let requestRangeNotSatisfiable = Status(code: .requestRangeNotSatisfiable, info: "REQUEST RANGE NOT SATISFIABLE")
      public static let expectationFailed = Status(code: .expectationFailed, info: "EXPECTATION FAILED")

      // 5XX

      public static let internalServerError = Status(code: .internalServerError, info: "INTERNAL SERVER ERROR")
      public static let notImplemented = Status(code: .notImplemented, info: "NOT IMPLEMENTED")
      public static let badGateway = Status(code: .badGateway, info: "BAD GATEWAY")
      public static let serviceUnavailable = Status(code: .serviceUnavailable, info: "SERVICE UNAVAILABLE")
      public static let gatewayTimeout = Status(code: .gatewayTimeout, info: "GATEWAY TIMEOUT")
      public static let httpVersionNotSupported = Status(code: .httpVersionNotSupported, info: "HTTP VERSION NOT SUPPORTED")

    }

    private init() {}

  }

}


extension HTTP.Request: CustomStringConvertible {

  public var description: String {
    var lines: [String] = []
    lines.append("\(method.rawValue.uppercased()) \(url.url?.absoluteString ?? "/") HTTP/\(version.major).\(version.minor)")
    for (header, values) in headers {
      for value in values {
        lines.append("\(header.lowercased().split(separator: "-").map { $0.capitalized }.joined(separator: "-")): \(value)")
      }
    }
    return lines.joined(separator: "\n")
  }

}
