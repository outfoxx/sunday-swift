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


/// A request body that can be streamed by the underlying transport.
public struct StreamingBody: Sendable {

  private enum Source: Sendable {
    case file(URL)
    case stream(@Sendable () throws -> InputStream)
    case bytes(@Sendable () throws -> InputStream)
  }

  private let source: Source

  /// Creates a streaming body from a fresh input stream factory.
  ///
  /// The factory is called each time the body is attached to a transport request.
  /// This allows redirects, authentication retries, and repeated operation executions
  /// to receive a new stream instead of reusing a consumed stream.
  public init(stream makeBodyStream: @escaping @Sendable () throws -> InputStream) {
    self.source = .stream(makeBodyStream)
  }

  /// Creates a streaming body from a local file URL.
  public static func file(_ url: URL) -> StreamingBody {
    StreamingBody(source: .file(url))
  }

  /// Creates a streaming body from an async byte sequence factory.
  public static func bytes<S>(
    _ makeBytes: @escaping @Sendable () -> S
  ) -> StreamingBody where S: AsyncSequence & Sendable, S.Element == Data {
    StreamingBody(source: .bytes {
      try AsyncSequenceInputStream.makeInputStream(bytes: makeBytes())
    })
  }

  func makeInputStream() throws -> InputStream {
    switch source {
    case .file(let url):
      guard let stream = InputStream(url: url) else {
        throw SundayError.requestEncodingFailed(reason: .streamCreationFailed)
      }
      return stream
    case .stream(let makeStream):
      return try makeStream()
    case .bytes(let makeStream):
      return try makeStream()
    }
  }

  private init(source: Source) {
    self.source = source
  }

}
