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
import Synchronization


let streamingBodyRequestPropertyKey = "io.outfoxx.sunday.streamingBody"


final class StreamingBodyRequestProperty: Sendable {

  let body: StreamingBody
  private let replayError = Mutex<Error?>(nil)

  init(body: StreamingBody) {
    self.body = body
  }

  var recordedReplayError: Error? {
    replayError.withLock { $0 }
  }

  func recordReplayError(_ error: Error) {
    replayError.withLock { currentError in
      if currentError == nil {
        currentError = error
      }
    }
  }

}

extension URLRequest {
  var streamingBodyProperty: StreamingBodyRequestProperty? {
    URLProtocol.property(forKey: streamingBodyRequestPropertyKey, in: self) as? StreamingBodyRequestProperty
  }

  func withoutStreamingBodyProperty() -> URLRequest {
    guard let copy = (self as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
      preconditionFailure("Foundation URLRequest must bridge to NSMutableURLRequest")
    }
    URLProtocol.removeProperty(forKey: streamingBodyRequestPropertyKey, in: copy)
    return copy as URLRequest
  }
}

public extension URLRequest {
  /// Returns a fresh stream from the body's factory without consuming the current stream.
  /// Throws when a one-shot stream has no replay factory. Data bodies are copied without work.
  func replayingBody() throws -> URLRequest {
    guard httpBodyStream != nil else { return self }
    guard let property = streamingBodyProperty else { throw URLError(.requestBodyStreamExhausted) }
    return try with(streamingBody: property.body)
  }

  /// Replaces the body with an adapter-owned stream factory, including its native replay capability.
  /// Use this when a transformed streaming body must support redirects or authentication replay.
  func with(streamingBody: StreamingBody) throws -> URLRequest {
    var request = self
    request.httpBody = nil
    request.httpBodyStream = try streamingBody.makeInputStream()
    guard let copy = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
      throw SundayError.requestEncodingFailed(reason: .streamCreationFailed)
    }
    URLProtocol.setProperty(StreamingBodyRequestProperty(body: streamingBody),
                            forKey: streamingBodyRequestPropertyKey, in: copy)
    return copy as URLRequest
  }
}
