/*
 * Copyright 2021 Outfox, Inc.
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


public extension HTTPURLResponse {

  /**
   Returns the value which corresponds to the given header
   field. Note that, in keeping with the HTTP RFC, HTTP header field
   names are case-insensitive.

   - Attention: This backports an equivalent method introduced in `macOS 10.15`, `iOS 13`, `tvOS 13`, and `watchOS 6`.

   - Parameters:
     - field: The header field name to use for the lookup (case-insensitive).
   - Returns: The value associated with the given header field, or nil if there  is no value associated with
              the given header field.
   */

  func value(forHttpHeaderField field: String) -> String? {
    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
      return value(forHTTPHeaderField: field)
    }
    else {
      return allHeaderFields.first { $0.key.description.lowercased() == field.lowercased() }
        .map { String(describing: $0.value) }
    }
  }

}
