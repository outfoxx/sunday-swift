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

/// A credential receipt used to conditionally invalidate a rejected token.
public struct TokenLease: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  let key: String
  public let tokens: TokenSet
  private let rejection: @Sendable () async throws -> Bool

  init(key: String, tokens: TokenSet, rejection: @escaping @Sendable () async throws -> Bool = { false }) {
    self.key = key
    self.tokens = tokens
    self.rejection = rejection
  }

  /// Asks the originating provider to reject this credential without disturbing newer credentials.
  public func invalidate() async throws -> Bool {
    do {
      return try await rejection()
    }
    catch let error where isRequestCancellation(error) {
      throw error
    }
    catch is AuthorizationRequiredError {
      throw AuthorizationRequiredError()
    }
    catch let error as TokenProviderError {
      throw error
    }
    catch { throw TokenProviderError() }
  }

  public var description: String { "TokenLease()" }
  public var debugDescription: String { description }
}
