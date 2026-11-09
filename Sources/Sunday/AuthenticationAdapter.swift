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

/// Applies selected operation credentials and reports rejected tokens to their original owners.
/// Providers own their lifecycle; explicitly supply TokenManager when Sunday should cache credentials.
public struct AuthenticationAdapter: RequestAdapter, ResponseAdapter {
  private let providers: [String: any TokenProvider]

  /// Creates an authentication adapter without acquiring or caching credentials.
  public init(providers: [String: any TokenProvider]) { self.providers = providers }

  /// Acquires once for this attempt and preserves the original credential receipts.
  public func adapt(request: URLRequest) async throws -> URLRequest {
    guard !request.securityBindings.isEmpty else { return request }
    let security = RequestSecurity(bindings: request.securityBindings, providers: providers)
    let (authorized, leases) = try await security.authorize(request)
    return try authorized.withSecurity(request.securityBindings, leases: leases)
  }

  /// Invalidates rejected credentials even when retrying this request is unsafe or the budget is exhausted.
  public func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
    guard let context = request.securityProperty else { return response }
    let security = RequestSecurity(bindings: context.bindings, providers: providers)
    try await security.reject(response, for: request, leases: context.leases)
    return try security.redact(response)
  }
}
