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

// Shared by authentication feedback and the independent bounded retry policy.
enum BearerChallenge {
  static func token(in header: String?) -> String? {
    guard let header else { return nil }
    let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
    let token = parts[1].drop(while: { $0 == " " })
    guard !token.isEmpty, !token.contains(where: { $0.isWhitespace }) else { return nil }
    return String(token)
  }

  static func isInvalidToken(_ header: String) -> Bool {
    var parts: [String] = []
    var current = ""
    var quoted = false
    var escaped = false
    for character in header {
      if escaped { escaped = false }
 else if quoted, character == "\\" { escaped = true }
 else if character == "\"" { quoted.toggle() }
 else if !quoted, character == "," {
        parts.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue
      }
      current.append(character)
    }
    guard !quoted, !escaped else { return false }
    parts.append(current.trimmingCharacters(in: .whitespaces))
    var bearer = false
    for var part in parts {
      if let range = part.range(of: #"^[a-zA-Z][a-zA-Z0-9_-]*\s+(?!\s*=)"#, options: .regularExpression) {
        bearer = part[range].trimmingCharacters(in: .whitespaces).lowercased() == "bearer"
        part.removeSubrange(range)
      }
      else if part.range(of: #"^[a-zA-Z][a-zA-Z0-9_-]*$"#, options: .regularExpression) != nil { bearer = false }
      if bearer, part.range(
        of: #"^(?i:error)\s*=\s*(?:"invalid_token"|invalid_token)$"#,
        options: .regularExpression
      ) != nil { return true }
    }
    return false
  }
}
