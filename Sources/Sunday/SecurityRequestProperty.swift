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

private let securityRequestPropertyKey = "io.outfoxx.sunday.security"

final class SecurityRequestProperty: Sendable {
  let security: RequestSecurity
  init(security: RequestSecurity) { self.security = security }
}

extension URLRequest {
  var securityProperty: SecurityRequestProperty? {
    URLProtocol.property(forKey: securityRequestPropertyKey, in: self) as? SecurityRequestProperty
  }

  func withSecurity(_ bindings: [SecurityBinding], manager: TokenManager?) async throws -> URLRequest {
    guard !bindings.isEmpty else { return self }
    guard let manager else { throw TokenProviderError() }
    let security = RequestSecurity(bindings: bindings, manager: manager)
    let (authorized, _) = try await security.authorize(self, previouslyAuthorized: false)
    guard let copy = (authorized as NSURLRequest).mutableCopy() as? NSMutableURLRequest
    else { throw TokenProviderError() }
    URLProtocol.setProperty(SecurityRequestProperty(security: security), forKey: securityRequestPropertyKey, in: copy)
    return copy as URLRequest
  }
}
