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
  public var description: String { "TokenLease()" }
  public var debugDescription: String { description }
}
