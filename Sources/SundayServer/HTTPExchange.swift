//
//  HTTPExchange.swift
//  
//
//  Created by Kevin Wooten on 6/17/19.
//

import Foundation
import Sunday
import RxSwift


extension HTTP {

  public struct Request {

    public let method: HTTP.Method
    public let url: URL
    public let version: HTTP.Version
    public let headers: HTTP.Headers
    public let rawHeaders: HTTP.RawHeaders
    public let body: Data?
    
  }


  public struct Response {

    public struct Status : CustomStringConvertible {
      public let code: StatusCode
      public let info: String

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

    public enum Entity {
      case data(Data)
      case stream(Observable<Data>)
      case value((MediaTypeEncoder) throws -> Data)
      case none
    }

    public let status: Status
    public let headers: HTTP.Headers
    public let entity: Entity

    public static func ok(data: Data? = nil, headers: HTTP.Headers = [:]) -> Response {
      return Response(status: .ok, headers: headers, entity: data.flatMap { .data($0) } ?? .none)
    }

    public static func ok<T>(value: T, headers: HTTP.Headers = [:]) -> Response where T : Encodable {
      return Response(status: .ok, headers: headers, entity: .value { encoder in try encoder.encode(value) })
    }

    public static func notFound(message: String? = nil, headers: HTTP.Headers = [:]) -> Response {
      return Response(status: .notFound, headers: headers, entity: message.flatMap { .data($0.data(using: .utf8) ?? Data()) } ?? .none)
    }

    public static func badRequest(message: String? = nil, headers: HTTP.Headers = [:]) -> Response {
      return Response(status: .badRequest, headers: headers, entity: message.flatMap { .data($0.data(using: .utf8) ?? Data()) } ?? .none)
    }

    public static func internalServerError(message: String? = nil, headers: HTTP.Headers = [:]) -> Response {
      return Response(status: .internalServerError, headers: headers, entity: message.flatMap { .data($0.data(using: .utf8) ?? Data()) } ?? .none)
    }

  }

}
