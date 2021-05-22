//
//  HTTP.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public struct HTTP {

  public enum Method: String {
    case options = "OPTIONS"
    case get     = "GET"
    case head    = "HEAD"
    case post    = "POST"
    case put     = "PUT"
    case patch   = "PATCH"
    case delete  = "DELETE"
    case trace   = "TRACE"
    case connect = "CONNECT"
  }

  public enum StatusCode: Int, Codable, ExpressibleByIntegerLiteral {
    case `continue` = 100
    case switchingProtocols = 101
    
    case ok = 200
    case created = 201
    case accepted = 202
    case nonAuthoritativeInformation = 203
    case noContent = 204
    case resetContent = 205
    case partialContent = 206
    
    case multipleChoices = 300
    case movedPermanently = 301
    case found = 302
    case seeOther = 303
    case notModified = 304
    case useProxy = 305
    case temporaryRedirect = 307
    
    case badRequest = 400
    case unauthenticated = 401
    case paymentRequired = 402
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case notAcceptable = 406
    case proxyAuthenticationRequired = 407
    case requestTimeout = 408
    case conflict = 409
    case gone = 410
    case lengthRequired = 411
    case preconditionFailed = 412
    case requestEntityTooLarge = 413
    case requestUriTooLong = 414
    case unsupportedMediaType = 415
    case requestRangeNotSatisfiable = 416
    case expectationFailed = 417
    
    case internalServerError = 500
    case notImplemented = 501
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504
    case httpVersionNotSupported = 505
    
    public init(integerLiteral value: IntegerLiteralType) {
      self.init(rawValue: value)!
    }
  }
  
  public static let statusText: [StatusCode: String] = [
    .continue: "Continue",
    .switchingProtocols: "Switching Protocols",
    
    .ok: "OK",
    .created: "Created",
    .accepted: "Accepted",
    .nonAuthoritativeInformation: "Non Authoritative Information",
    .noContent: "No Content",
    .resetContent: "ResetContent",
    .partialContent: "Partial Content",
    
    .multipleChoices: "Multiple Choices",
    .movedPermanently: "Moved Permanently",
    .found: "Found",
    .seeOther: "See Other",
    .notModified: "Not Modified",
    .useProxy: "Use Proxy",
    .temporaryRedirect: "Temporary Redirect",
    
    .badRequest: "Bad Request",
    .unauthenticated: "Unauthenticated",
    .paymentRequired: "Payment Required",
    .forbidden: "Forbidden",
    .notFound: "Not Found",
    .methodNotAllowed: "Method Not Allowed",
    .notAcceptable: "Not Acceptable",
    .proxyAuthenticationRequired: "Proxy Authentication Required",
    .requestTimeout: "Request Timeout",
    .conflict: "Conflict",
    .gone: "Gone",
    .lengthRequired: "Length Required",
    .preconditionFailed: "Precondition Failed",
    .requestEntityTooLarge: "Request Entity Too Large",
    .requestUriTooLong: "Request Uri Too Long",
    .unsupportedMediaType: "Unsupported Media Type",
    .requestRangeNotSatisfiable: "Request Range Not Satisfiable",
    .expectationFailed: "Expectation Failed",
    
    .internalServerError: "Internal Server Error",
    .notImplemented: "Not mplemented",
    .badGateway: "Bad Gateway",
    .serviceUnavailable: "Service Unavailable",
    .gatewayTimeout: "Gateway Timeout",
    .httpVersionNotSupported: "Http Version Not Supported",
  ]

  public struct Header : Equatable {
    var name: String
    var value: String
  }

  public typealias HeaderList = [Header]
  public typealias Headers = [String: [String]]
  public typealias RawHeaders = [(name: String, value: Data)]
  public typealias Version = (major: Int, minor: Int)

  public struct StdHeaders {

    public static let accept = "accept"
    public static let authorization = "authorization"
    public static let connection = "connection"
    public static let contentLength = "content-length"
    public static let contentType = "content-type"
    public static let location = "location"
    public static let server = "server"
    public static let transferEncoding = "transfer-encoding"
    public static let userAgent = "user-agent"
    public static let cookie = "cookie"
    public static let setCookie = "set-cookie"
    public static let expect = "expect"

  }

}


public typealias Parameters = [String: Any?]


extension URL {

  public enum Scheme: String {
    case http
    case https
  }

}
