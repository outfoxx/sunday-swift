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

/// Resolved, non-secret inputs for an application credential provider.
public struct TokenRequest: Sendable {
  public let binding: SecurityBinding
  public let clientIdentity: String
  public let grantIdentity: String?

  /// Creates provider input from a selected binding and application configuration.
  public init(binding: SecurityBinding, clientIdentity: String, grantIdentity: String? = nil) {
    self.binding = binding
    self.clientIdentity = clientIdentity
    self.grantIdentity = grantIdentity
  }
}
