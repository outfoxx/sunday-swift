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


/// A request body prepared for a native transport request.
public enum PreparedRequestBody: Sendable {

  /// A fully encoded request body.
  case data(Data, contentType: MediaType)

  /// A streaming request body.
  case stream(StreamingBody, contentType: MediaType?)

  var contentType: MediaType? {
    switch self {
    case .data(_, let contentType):
      return contentType
    case .stream(_, let contentType):
      return contentType
    }
  }

}
