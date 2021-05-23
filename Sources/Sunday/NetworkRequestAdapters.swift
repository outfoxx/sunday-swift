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

import Combine
import Foundation


/// Composing request adapter that applies another request adapter
/// only if the request's hostname is in a set of matching hostnames.
open class HostMatchingAdapter: NetworkRequestAdapter {

  private let hostnames: Set<String>
  private let adapter: NetworkRequestAdapter

  public convenience init(hostname: String, adapter: NetworkRequestAdapter) {
    self.init(hostnames: [hostname], adapter: adapter)
  }

  public init(hostnames: Set<String>, adapter: NetworkRequestAdapter) {
    self.hostnames = hostnames
    self.adapter = adapter
  }

  public func adapt(requestFactory: NetworkRequestFactory, urlRequest: URLRequest) -> AdaptResult {
    guard hostnames.contains(urlRequest.url?.host ?? "") else {
      return Just(urlRequest)
        .setFailureType(to: Error.self)
        .eraseToAnyPublisher()
    }
    return adapter.adapt(requestFactory: requestFactory, urlRequest: urlRequest)
  }

}


open class HeaderTokenAuthorizingAdapter: NetworkRequestAdapter {

  private let header: String
  private let tokenHeaderType: String
  private let token: String

  public init(tokenHeaderType: String, token: String, header: String = HTTP.StdHeaders.authorization) {
    self.header = header
    self.tokenHeaderType = tokenHeaderType
    self.token = token
  }


  // MARK: NetworkRequestAdapter

  public func adapt(requestFactory: NetworkRequestFactory, urlRequest: URLRequest) -> AdaptResult {

    let authRequest = urlRequest.adding(httpHeaders: [header: ["\(tokenHeaderType) \(token)"]])

    return Just(authRequest)
      .setFailureType(to: Error.self)
      .eraseToAnyPublisher()
  }

}


public struct TokenAuthorization {
  public let token: String
  public let expires: Date

  public init(token: String, expires: Date) {
    self.token = token
    self.expires = expires
  }
}

open class RefreshingHeaderTokenAuthorizingAdapter: NetworkRequestAdapter {

  public typealias RefreshResult = AnyPublisher<TokenAuthorization, Error>

  private let header: String
  private let tokenHeaderType: String
  private var authorization: TokenAuthorization?
  private var refresh: (NetworkRequestFactory) throws -> RefreshResult

  public init(
    tokenHeaderType: String,
    header: String = HTTP.StdHeaders.authorization,
    refresh: @escaping (NetworkRequestFactory) throws -> RefreshResult
  ) {
    self.header = header
    self.tokenHeaderType = tokenHeaderType
    self.refresh = refresh
  }

  func update(urlRequest: URLRequest, accessToken: String) -> URLRequest {
    urlRequest.adding(httpHeaders: [header: ["\(tokenHeaderType) \(accessToken)"]])
  }


  // MARK: NetworkRequestFactory

  public func adapt(requestFactory: NetworkRequestFactory, urlRequest: URLRequest) -> AdaptResult {
    guard let authorization = authorization, authorization.expires > Date() else {
      do {
        return try refresh(requestFactory)
          .map { authorization in
            self.authorization = authorization
            return self.update(urlRequest: urlRequest, accessToken: authorization.token)
          }
          .eraseToAnyPublisher()
      }
      catch {
        return Fail(error: error).eraseToAnyPublisher()
      }
    }

    return Just(update(urlRequest: urlRequest, accessToken: authorization.token))
      .setFailureType(to: Error.self)
      .eraseToAnyPublisher()
  }

}
