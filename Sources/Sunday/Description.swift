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


/**
 * Builder for simplifying the generation of description
 * values for types implementing `CustomStringConvertible`
 */
public struct DescriptionBuilder {

  private var name: String
  private var entries = [(String, Any?)]()

  private init(_ name: String, _ entries: [(String, Any?)] = []) {
    self.name = name
    self.entries = entries
  }

  public init(_ type: Any.Type) {
    self.init(String(describing: type))
  }

  public func add(_ value: Any?, named name: String) -> DescriptionBuilder {
    var entries = self.entries
    entries.append((name, value))
    return DescriptionBuilder(self.name, entries)
  }

  public func build() -> String {
    return "\(name)(\(entries.map { "\($0)=\($1 ?? "nil")" }.joined(separator: ", ")))"
  }

}
