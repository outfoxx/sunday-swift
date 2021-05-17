//
//  URLRequests.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

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

}
