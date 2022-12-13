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

public typealias PathEncoder = (Any) -> String


public typealias PathEncoders = [String: PathEncoder]


// swiftlint:disable:next force_cast
public let uuidPathEncoder: PathEncoder = { ($0 as! UUID).uuidString }


public extension PathEncoders {

  static var `default`: PathEncoders {
    return [
      String(describing: UUID.self): uuidPathEncoder
    ]
  }

  func firstSupported(value: Any) -> String? {
    let typeName = String(describing: type(of: value))
    return self[typeName]?(value)
  }

  func add<T>(converter: @escaping (T) -> String) -> PathEncoders {
    // swiftlint:disable:next force_cast
    let encoder: PathEncoder = { value in converter((value as! T)) }
    return merging([String(describing: T.self): encoder], uniquingKeysWith: { $1 })
  }

}
