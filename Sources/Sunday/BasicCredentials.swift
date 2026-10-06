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

/// Basic authentication inputs encoded by the runtime.
public struct BasicCredentials: BasicCredential, CustomStringConvertible, CustomDebugStringConvertible {
  public let username: String
  public let password: String
  /// Stores application-supplied credentials without encoding them into generated metadata.
  public init(username: String, password: String) { self.username = username; self.password = password }
  public var description: String { "BasicCredentials()" }
  public var debugDescription: String { description }
}
