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


/// Composing request adapter that applies another request adapter
/// only if the request's hostname is in a set of matching hostnames.
public final class HostMatchingAdapter: RequestAdapter, ResponseAdapter {

  private let hostnames: Set<String>
  private let adapter: RequestAdapter

  public convenience init(hostname: String, adapter: RequestAdapter) {
    self.init(hostnames: [hostname], adapter: adapter)
  }

  public init(hostnames: Set<String>, adapter: RequestAdapter) {
    self.hostnames = hostnames
    self.adapter = adapter
  }

  public func adapt(request urlRequest: URLRequest) async throws -> URLRequest {
    guard hostnames.contains(urlRequest.url?.host ?? "") else {
      return urlRequest
    }
    return try await adapter.adapt(request: urlRequest)
  }

  /// Applies response feedback only for requests matched by this adapter.
  public func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
    guard hostnames.contains(request.url?.host ?? ""), let adapter = adapter as? any ResponseAdapter else {
      return response
    }
    return try await adapter.adapt(response: response, for: request)
  }

}


/// Request adapter that adds a static token authorization header.
public final class HeaderTokenAuthorizingAdapter: RequestAdapter, ResponseAdapter {

  private let header: String
  private let tokenHeaderType: String
  private let token: String

  public init(tokenHeaderType: String, token: String, header: String = HTTP.StdHeaders.authorization) {
    self.header = header
    self.tokenHeaderType = tokenHeaderType
    self.token = token
  }


  // MARK: RequestAdapter

  public func adapt(request urlRequest: URLRequest) async throws -> URLRequest {

    return urlRequest.adding(httpHeaders: [header: ["\(tokenHeaderType) \(token)"]])
  }

  /// Static rejected credentials cannot be repaired by replaying the request.
  public func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
    if response.statusCode == 401, tokenHeaderType.lowercased() == "bearer",
       BearerChallenge.token(in: request.value(forHTTPHeaderField: header)) == token,
       BearerChallenge.isInvalidToken(response.value(forHTTPHeaderField: "WWW-Authenticate") ?? "") {
      throw TokenRejectedError(response: response)
    }
    return response
  }

}


/// A refreshed token authorization value.
public struct TokenAuthorization: Sendable {
  public let token: String
  public let expires: Date

  /// Initializes a refreshed token authorization value.
  public init(token: String, expires: Date) {
    self.token = token
    self.expires = expires
  }
}

/// Request adapter that adds a refreshed token authorization header.
public final class RefreshingHeaderTokenAuthorizingAdapter: RequestAdapter, ResponseAdapter {

  private let header: String
  private let tokenHeaderType: String
  private let store: AuthorizationStore

  public init(
    tokenHeaderType: String,
    header: String = HTTP.StdHeaders.authorization,
    refresh: @escaping @Sendable () async throws -> TokenAuthorization
  ) {
    self.header = header
    self.tokenHeaderType = tokenHeaderType
    self.store = AuthorizationStore(refresh: refresh)
  }

  func update(urlRequest: URLRequest, accessToken: String) -> URLRequest {
    urlRequest.adding(httpHeaders: [header: ["\(tokenHeaderType) \(accessToken)"]])
  }


  // MARK: RequestAdapter

  public func adapt(request urlRequest: URLRequest) async throws -> URLRequest {
    return update(urlRequest: urlRequest, accessToken: try await store.authorization().token)
  }

  /// Expires only the rejected authorization, even if this request cannot be retried.
  public func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
    if response.statusCode == 401, tokenHeaderType.lowercased() == "bearer",
       let rejected = request.value(forHTTPHeaderField: header),
       BearerChallenge.isInvalidToken(response.value(forHTTPHeaderField: "WWW-Authenticate") ?? "") {
      await store.invalidate(token: BearerChallenge.token(in: rejected))
    }
    return response
  }

}

private actor AuthorizationStore {

  private var authorization: TokenAuthorization?
  private var refreshTask: Task<TokenAuthorization, any Error>?
  private let refresh: @Sendable () async throws -> TokenAuthorization

  init(refresh: @escaping @Sendable () async throws -> TokenAuthorization) {
    self.refresh = refresh
  }

  func invalidate(token: String?) {
    if let authorization, token == authorization.token { self.authorization = nil }
  }

  func authorization() async throws -> TokenAuthorization {
    if let authorization, authorization.expires > Date() {
      return authorization
    }

    if let refreshTask {
      return try await refreshTask.value
    }

    let refreshTask = Task {
      try await refresh()
    }
    self.refreshTask = refreshTask

    do {
      let authorization = try await refreshTask.value
      self.authorization = authorization
      self.refreshTask = nil
      return authorization
    }
    catch {
      self.refreshTask = nil
      throw error
    }
  }

}
