//
//  Authorizers.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Alamofire
import Foundation


class HeaderTokenAuthorizer: RequestAdapter {

  private let header: String
  private let tokenType: String
  private let token: String

  init(tokenType: String, token: String, header: String = HTTP.StdHeaders.authorization) {
    self.header = header
    self.tokenType = tokenType
    self.token = token
  }

  // MARK: RequestAdapter

  func adapt(_ urlRequest: URLRequest) throws -> URLRequest {

    var urlRequest = urlRequest

    urlRequest.allHTTPHeaderFields?[header] = "\(tokenType) \(token)"

    return urlRequest
  }

}
