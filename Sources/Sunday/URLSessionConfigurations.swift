/*
 * Copyright 2021 Outfox, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation


public extension URLSessionConfiguration {

  static let restTimeoutIntervalForRequestDefault = TimeInterval(15)
  static let restTimeoutIntervalForResourceDefault = TimeInterval(60)

  static func rest(
    from config: URLSessionConfiguration = .default,
    requestTimeout: TimeInterval? = nil,
    resourceTimeout: TimeInterval? = nil
  ) -> URLSessionConfiguration {

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

  static func rest(from config: URLSessionConfiguration = .default, timeout: TimeInterval) -> URLSessionConfiguration {
    return Self.rest(from: config, requestTimeout: timeout, resourceTimeout: timeout)
  }

}
