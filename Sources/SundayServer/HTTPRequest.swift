//
//  HTTPRequest.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

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
