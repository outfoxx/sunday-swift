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
    case ok = 200
    case created = 201
    case noData = 204
    case badRequest = 400
    case unauthenticated = 401
    case notFound = 404
    case internalServerError = 500
  }

  public typealias Headers = [String: [String]]
  public typealias RawHeaders = [(name: String, value: Data)]
  public typealias Version = (major: Int, minor: Int)

  public struct StandardHeaders {

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
