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
@testable import Sunday
import XCTest


class NetworkRequestAdapterTests: XCTestCase {

  static let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")
  static let exampleURL = URL(string: "http://example.com")!

  func testHostMatchingAdapter() async throws {

    let marker = MarkingAdapter()
    let adapter = HostMatchingAdapter(hostname: "example.com", adapter: marker)

    let matched = try await adapter.adapt(
      requestFactory: Self.requestFactory,
      urlRequest: URLRequest(url: Self.exampleURL)
    )
    XCTAssertTrue(matched.isMarked)

    let unmatched = try await adapter.adapt(
      requestFactory: Self.requestFactory,
      urlRequest: URLRequest(url: URL(string: "http://other.com")!)
    )
    XCTAssertFalse(unmatched.isMarked)


    let setAdapater = HostMatchingAdapter(hostnames: ["example.com", "api.example.com"], adapter: marker)

    let setMatched =
      try await setAdapater.adapt(
        requestFactory: Self.requestFactory,
        urlRequest: URLRequest(url: URL(string: "http://api.example.com")!)
      )
    XCTAssertTrue(setMatched.isMarked)

    let setUnatched =
      try await adapter.adapt(
        requestFactory: Self.requestFactory,
        urlRequest: URLRequest(url: URL(string: "http://other.example.com")!)
      )
    XCTAssertFalse(setUnatched.isMarked)
  }

  func testTokenAuth() async throws {

    let adapter = HeaderTokenAuthorizingAdapter(tokenHeaderType: "Bearer", token: "12345")

    let request =
      try await adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 12345")
  }

  func testRefreshingTokenAuth() async throws {

    var count = 0

    let refresher = { (_: NetworkRequestFactory) -> TokenAuthorization in

      count += 1

      return TokenAuthorization(token: "\(count)", expires: Date().addingTimeInterval(0.2))
    }

    let adapter = RefreshingHeaderTokenAuthorizingAdapter(tokenHeaderType: "Bearer", refresh: refresher)

    let request1 =
      try await adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))

    let request2 =
    try await adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))

    try await Task.sleep(nanoseconds: UInt64(0.25 * 1_000_000_000))

    let request3 =
      try await adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))

    XCTAssertEqual(request1.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 1")
    XCTAssertEqual(request2.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 1")
    XCTAssertEqual(request3.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 2")
  }

}


extension URLRequest {

  var isMarked: Bool { value(forHTTPHeaderField: "x-marked") == "true" }

}

struct MarkingAdapter: NetworkRequestAdapter {

  func adapt(requestFactory: NetworkRequestFactory, urlRequest: URLRequest) -> URLRequest {
    return urlRequest.adding(httpHeaders: ["x-marked": ["true"]])
  }
}
