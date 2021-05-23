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

    let matchedRecorder =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()

    let matched = try wait(for: matchedRecorder.next(), timeout: 1.0)
    XCTAssertTrue(matched.isMarked)

    let unmatchedRecorder =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: URL(string: "http://other.com")!))
        .record()

    let unmatched = try wait(for: unmatchedRecorder.next(), timeout: 1.0)
    XCTAssertFalse(unmatched.isMarked)


    let setAdapater = HostMatchingAdapter(hostnames: ["example.com", "api.example.com"], adapter: marker)

    let setMatchedRecorder =
      setAdapater.adapt(
        requestFactory: Self.requestFactory,
        urlRequest: URLRequest(url: URL(string: "http://api.example.com")!)
      )
      .record()

    let setMatched = try wait(for: setMatchedRecorder.next(), timeout: 1.0)
    XCTAssertTrue(setMatched.isMarked)

    let setUnatchedRecorder =
      adapter.adapt(
        requestFactory: Self.requestFactory,
        urlRequest: URLRequest(url: URL(string: "http://other.example.com")!)
      )
      .record()

    let setUnatched = try wait(for: setUnatchedRecorder.next(), timeout: 1.0)
    XCTAssertFalse(setUnatched.isMarked)
  }

  func testTokenAuth() throws {

    let adapter = HeaderTokenAuthorizingAdapter(tokenHeaderType: "Bearer", token: "12345")

    let requestPublisher =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()

    let request = try wait(for: requestPublisher.next(), timeout: 1.0)

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

    let request1Recorder =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()
    let request1 = try wait(for: request1Recorder.next(), timeout: 0.05)

    let request2Recorder =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()
    let request2 = try wait(for: request2Recorder.next(), timeout: 0.05)

    Thread.sleep(until: Date().advanced(by: 0.25))

    let request3Recorder =
      adapter.adapt(requestFactory: Self.requestFactory, urlRequest: URLRequest(url: Self.exampleURL))
        .record()
    let request3 = try wait(for: request3Recorder.next(), timeout: 0.05)

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
