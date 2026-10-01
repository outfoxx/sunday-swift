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

extension URLSession {
  func securedData(for request: URLRequest) async throws -> (Data, URLResponse) {
    guard let security = request.securityProperty?.security else { return try await data(for: request) }
    guard configuration.identifier == nil else { throw TokenProviderError() }
    let budget = AuthenticationRecoveryBudget()
    let delegate = ManagedSecuritySessionDelegate(delegate: delegate)
    var (authorized, leases) = try await security.authorize(request, previouslyAuthorized: true)
    while true {
      delegate.rejectedResponse.withLock { $0 = nil }
      let (data, rawResponse): (Data, URLResponse)
      do { (data, rawResponse) = try await self.data(for: authorized, delegate: delegate) }
 catch {
        guard !Task.isCancelled, let response = delegate.rejectedResponse.withLock({ $0 }) else {
          throw sanitizedTransportError(error)
        }
        data = Data()
        rawResponse = response
      }
      guard let response = rawResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
      if try await security.recover(response, request: authorized, leases: leases, budget: budget) {
        (authorized, leases) = try await security.authorize(request, previouslyAuthorized: true)
        continue
      }
      return try (data, security.redact(response))
    }
  }

  func securedBytes(
    for request: URLRequest,
    budget: AuthenticationRecoveryBudget
  ) async throws -> (AsyncBytes, URLResponse) {
    guard let security = request.securityProperty?.security else { return try await bytes(for: request) }
    guard configuration.identifier == nil else { throw TokenProviderError() }
    let delegate = ManagedSecuritySessionDelegate(delegate: delegate)
    var (authorized, leases) = try await security.authorize(request, previouslyAuthorized: true)
    while true {
      delegate.rejectedResponse.withLock { $0 = nil }
      let (bytes, rawResponse): (AsyncBytes, URLResponse)
      do { (bytes, rawResponse) = try await self.bytes(for: authorized, delegate: delegate) }
 catch {
        guard !Task.isCancelled, let response = delegate.rejectedResponse.withLock({ $0 }) else {
          throw sanitizedTransportError(error)
        }
        if try await security.recover(response, request: authorized, leases: leases, budget: budget) {
          (authorized, leases) = try await security.authorize(request, previouslyAuthorized: true)
          continue
        }
        throw SundayError.responseValidationFailed(reason: .unacceptableStatusCode(
          response: try security.redact(response), data: nil
        ))
      }
      guard let response = rawResponse as? HTTPURLResponse else {
        bytes.task.cancel()
        throw URLError(.badServerResponse)
      }
      if response.statusCode == 401 {
        bytes.task.cancel()
        if try await security.recover(response, request: authorized, leases: leases, budget: budget) {
          (authorized, leases) = try await security.authorize(request, previouslyAuthorized: true)
          continue
        }
      }
      if (400 ..< 600).contains(response.statusCode) { bytes.task.cancel() }
      return try (bytes, security.redact(response))
    }
  }

  private func sanitizedTransportError(_ error: any Error) -> any Error {
    if error is CancellationError || Task.isCancelled { return CancellationError() }
    return URLError((error as? URLError)?.code ?? .unknown)
  }
}
