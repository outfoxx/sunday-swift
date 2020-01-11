//
//  ResponseDelegate.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


class ResponseDelegate: NSObject, URLSessionTaskDelegate {

  let options: URLSession.RequestOptions

  init(options: URLSession.RequestOptions) {
    self.options = options
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask,
                         willPerformHTTPRedirection response: HTTPURLResponse,
                         newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    if options.contains(.noFollowRedirects) {
      completionHandler(nil)
    }
    else {
      completionHandler(request)
    }
  }

}
