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

/// A fresh application-verified authorization result with an S256 PKCE verifier.
public struct AuthorizationGrant: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public let code: String
  public let redirectURI: String
  public let codeVerifier: String

  /// Creates a one-use authorization grant after the application verifies its authorization response.
  public init(code: String, redirectURI: String, codeVerifier: String) {
    self.code = code
    self.redirectURI = redirectURI
    self.codeVerifier = codeVerifier
  }

  public var description: String { "AuthorizationGrant()" }
  public var debugDescription: String { description }
}
