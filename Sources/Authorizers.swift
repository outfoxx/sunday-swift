//
//  Authorizer.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/20/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation
import Alamofire


class HeaderTokenAuthorizer: RequestAdapter {

  private let header: String
  private let tokenType: String
  private let token: String

  init(tokenType: String, token: String, header: String = HTTP.StandardHeaders.authorization) {
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
