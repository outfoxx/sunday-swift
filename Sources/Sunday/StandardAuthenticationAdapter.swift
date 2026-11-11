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

/// Opt-in credential attachment, rejection feedback, and terminal bearer-rejection cancellation.
/// Supply TokenManager explicitly for Sunday-owned caching; external providers are never wrapped.
public struct StandardAuthenticationAdapter: RequestAdapter, ResponseAdapter {
  private let authentication: AuthenticationAdapter
  private let responses: ResponseAdapters

  /// Uses the supplied credential owners without acquiring tokens or taking ownership of their lifecycle.
  public init(providers: [String: any TokenProvider]) {
    authentication = AuthenticationAdapter(providers: providers)
    responses = ResponseAdapters([authentication, BearerTokenRejectionAdapter()])
  }

  /// Attaches credentials for the selected operation, leaving public requests unchanged.
  public func adapt(request: URLRequest) async throws -> URLRequest {
    try await authentication.adapt(request: request)
  }

  /// Reports rejection before stopping the exchange; does not renew or replay the request.
  public func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse {
    guard !request.securityBindings.isEmpty else { return response }
    do {
      return try await responses.adapt(response: response, for: request)
    }
    catch {
      if isRequestCancellation(error) { throw error }
      // Feedback failure must not bypass the explicitly selected stop policy.
      let redacted = try RequestSecurity(bindings: request.securityBindings, providers: [:]).redact(response)
      _ = try await BearerTokenRejectionAdapter().adapt(response: redacted, for: request)
      throw error
    }
  }
}
