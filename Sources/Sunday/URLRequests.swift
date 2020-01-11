//
//  URLRequests.swift
//  
//
//  Created by Kevin Wooten on 12/7/19.
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

}
