//
//  URLSessionConfigurations.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public extension URLSessionConfiguration {

  static let restTimeoutIntervalForResourceDefault = TimeInterval(60)
  static let restTimeoutIntervalForRequestDefault = TimeInterval(15)

  static func rest(from config: URLSessionConfiguration = .default,
                   requestTimeout: TimeInterval? = nil,
                   resourceTimeout: TimeInterval? = nil) -> URLSessionConfiguration {

    config.networkServiceType = .default
    config.httpShouldUsePipelining = true
    config.timeoutIntervalForRequest = requestTimeout ?? restTimeoutIntervalForRequestDefault
    config.timeoutIntervalForResource = resourceTimeout ?? restTimeoutIntervalForResourceDefault
    config.waitsForConnectivity = true
    config.allowsExpensiveNetworkAccess = true
    config.allowsConstrainedNetworkAccess = true
    config.allowsCellularAccess = true

    return config
  }

}
