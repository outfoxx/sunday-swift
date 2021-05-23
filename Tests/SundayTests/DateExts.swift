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


extension Date {

  static func millisecondDate() -> Date {
    let seconds = Date().timeIntervalSince1970
    return Date(timeIntervalSince1970: (seconds * 1000.0).rounded() / 1000.0)
  }

  init(millisecondsSince1970: Int64) {
    self.init(timeIntervalSince1970: Double(millisecondsSince1970) / 1000.0)
  }

  var millisecondsSince1970: Int64 {
    return Int64(timeIntervalSince1970 * 1000.0)
  }

}
