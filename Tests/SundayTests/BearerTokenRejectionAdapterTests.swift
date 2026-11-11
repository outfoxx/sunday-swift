/*
 * Copyright 2026 Outfox, Inc.
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
import Sunday
import Testing

struct BearerTokenRejectionAdapterTests {
  @Test(arguments: ["GET", "POST"], [200, 401, 403])
  func explicitPolicyFiltersWithoutReplay(method: String, status: Int) async throws {
    for challenge in ["Bearer error=invalid_token", "Basic error=invalid_token", "Bearer error=insufficient_scope"] {
      try await checkPolicy(method: method, status: status, challenge: challenge)
    }
  }

  private func checkPolicy(method: String, status: Int, challenge: String) async throws {
    let url = try #require(URL(string: "https://example.test"))
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = Data("untouched".utf8)
    request.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                               headerFields: ["WWW-Authenticate": challenge]))
    let adapter = BearerTokenRejectionAdapter()
    if status == 401 && challenge == "Bearer error=invalid_token" {
      for _ in 0..<2 {
        await #expect(throws: TokenRejectedError.self) { try await adapter.adapt(response: response, for: request) }
      }
    }
    else {
      #expect(try await adapter.adapt(response: response, for: request) === response)
    }
    request.setValue(nil, forHTTPHeaderField: "Authorization")
    #expect(try await adapter.adapt(response: response, for: request) === response)
    #expect(request.httpBody == Data("untouched".utf8))
  }
}
