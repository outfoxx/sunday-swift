//
//  NetworkRequestAdapterTests.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Combine
import CombineExpectations
import Foundation
@testable import Sunday
import XCTest


class NetworkRequestAdapterTests: XCTestCase {

  static let requestFactory = NetworkRequestFactory(baseURL: "http://example.com")
  static let exampleURL = URL(string: "http://example.com")!

  func testHostMatchingAdapter() throws {

    let marker = MarkingAdapter()
    let adapter = HostMatchingAdapter(hostname: "example.com", adapter: marker)

    let matched$ =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()

    let matched = try wait(for: matched$.next(), timeout: 1.0)
    XCTAssertTrue(matched.isMarked)

    let unmatched$ =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: URL(string: "http://other.com")!))
        .record()

    let unmatched = try wait(for: unmatched$.next(), timeout: 1.0)
    XCTAssertFalse(unmatched.isMarked)


    let setAdapater = HostMatchingAdapter(hostnames: ["example.com", "api.example.com"], adapter: marker)

    let setMatched$ =
      setAdapater.adapt(
        requestFactory: Self.requestFactory,
        urlRequest: URLRequest(url: URL(string: "http://api.example.com")!)
      )
      .record()

    let setMatched = try wait(for: setMatched$.next(), timeout: 1.0)
    XCTAssertTrue(setMatched.isMarked)

    let setUnatched$ =
      adapter.adapt(
        requestFactory: Self.requestFactory,
        urlRequest: URLRequest(url: URL(string: "http://other.example.com")!)
      )
      .record()

    let setUnatched = try wait(for: setUnatched$.next(), timeout: 1.0)
    XCTAssertFalse(setUnatched.isMarked)
  }

  func testTokenAuth() throws {

    let adapter = HeaderTokenAuthorizingAdapter(tokenHeaderType: "Bearer", token: "12345")

    let request$ =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()

    let request = try wait(for: request$.next(), timeout: 1.0)

    XCTAssertEqual(request.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 12345")
  }

  func testRefreshingTokenAuth() throws {

    var count = 0

    let refresher = { (_: NetworkRequestFactory) -> RefreshingHeaderTokenAuthorizingAdapter.RefreshResult in

      count += 1

      let auth = TokenAuthorization(token: "\(count)", expires: Date().addingTimeInterval(0.2))

      return Just(auth)
        .setFailureType(to: Error.self)
        .eraseToAnyPublisher()
    }

    let adapter = RefreshingHeaderTokenAuthorizingAdapter(tokenHeaderType: "Bearer", refresh: refresher)

    let request1$ =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()
    let request1 = try wait(for: request1$.next(), timeout: 0.05)

    let request2$ =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()
    let request2 = try wait(for: request2$.next(), timeout: 0.05)

    Thread.sleep(until: Date().advanced(by: 0.25))

    let request3$ =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()
    let request3 = try wait(for: request3$.next(), timeout: 0.05)

    XCTAssertEqual(request1.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 1")
    XCTAssertEqual(request2.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 1")
    XCTAssertEqual(request3.value(forHTTPHeaderField: HTTP.StdHeaders.authorization), "Bearer 2")
  }

}


extension URLRequest {

  var isMarked: Bool { value(forHTTPHeaderField: "x-marked") == "true" }

}

struct MarkingAdapter: NetworkRequestAdapter {

  func adapt(requestFactory: NetworkRequestFactory, urlRequest: URLRequest) -> AdaptResult {
    Just<URLRequest>(urlRequest.adding(httpHeaders: ["x-marked": ["true"]]))
      .setFailureType(to: Error.self)
      .eraseToAnyPublisher()
  }
}
