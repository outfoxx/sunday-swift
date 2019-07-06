//
//  HTTP.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/18/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation
import Alamofire


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

  public enum StatusCode: Int {
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
  }

  public typealias Headers = [String: [String]]
  public typealias RawHeaders = [(name: String, value: Data)]
  public typealias Version = (major: Int, minor: Int)

  public struct StdHeaders {

    public static let contentType = "Content-Type"
    public static let contentLength = "Content-Length"
    public static let accept = "Accept"
    public static let transferType = "Transfer-Type"
    public static let connection = "Connection"
    public static let server = "Server"
    public static let authorization = "Authorization"
    
  }

}


extension URL {

  public enum Scheme : String {
    case http
    case https
  }

}
