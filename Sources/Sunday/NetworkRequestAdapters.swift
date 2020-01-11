//
//  NetworkRequestAdapters.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import RxSwift


/// Composing request adapter that applies another request adapter
/// only if the request's hostname is in a set of matching hostnames.
public class HostMatchingAdapter: NetworkRequestAdapter {

  private let hostnames: Set<String>
  private let adapter: NetworkRequestAdapter

  public convenience init(hostname: String, adapter: NetworkRequestAdapter) {
    self.init(hostnames: [hostname], adapter: adapter)
  }

  public init(hostnames: Set<String>, adapter: NetworkRequestAdapter) {
    self.hostnames = hostnames
    self.adapter = adapter
  }

  public func adapt(requestManager: NetworkRequestManager, urlRequest: URLRequest) -> Single<URLRequest> {
    guard hostnames.contains(urlRequest.url?.host ?? "") else {
      return Single.just(urlRequest)
    }
    return adapter.adapt(requestManager: requestManager, urlRequest: urlRequest)
  }

}


public class HeaderTokenAuthorizingAdapter: NetworkRequestAdapter {

  private let header: String
  private let tokenHeaderType: String
  private let token: String

  public init(header: String = HTTP.StdHeaders.authorization, tokenHeaderType: String, token: String) {
    self.header = header
    self.tokenHeaderType = tokenHeaderType
    self.token = token
  }

  // MARK: NetworkRequestAdapter

  public func adapt(requestManager: NetworkRequestManager, urlRequest: URLRequest) -> Single<URLRequest> {

    var urlRequest = urlRequest

    urlRequest.allHTTPHeaderFields?[header] = "\(tokenHeaderType) \(token)"

    return Single.just(urlRequest)
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

public class RefreshingHeaderTokenAuthorizingAdapter: NetworkRequestAdapter {

  private let header: String
  private let tokenHeaderType: String
  private var authorization: TokenAuthorization?
  private var refresh: (NetworkRequestManager) throws -> Single<TokenAuthorization>

  public init(header: String = HTTP.StdHeaders.authorization, tokenHeaderType: String, refresh: @escaping (NetworkRequestManager) throws -> Single<TokenAuthorization>) {
    self.header = header
    self.tokenHeaderType = tokenHeaderType
    self.refresh = refresh
  }

  func update(urlRequest: URLRequest, accessToken: String) -> URLRequest {
    var urlRequest = urlRequest
    urlRequest.allHTTPHeaderFields?[header] = "\(tokenHeaderType) \(accessToken)"
    return urlRequest
  }

  // MARK: NetworkRequestManager

  public func adapt(requestManager: NetworkRequestManager, urlRequest: URLRequest) -> Single<URLRequest> {
    guard let authorization = authorization, authorization.expires > Date() else {
      do {
        return try refresh(requestManager)
          .map { authorization in
            self.authorization = authorization
            return self.update(urlRequest: urlRequest, accessToken: authorization.token)
          }
      }
      catch {
        return Single.error(error)
      }
    }

    return Single.just(update(urlRequest: urlRequest, accessToken: authorization.token))
  }

}
