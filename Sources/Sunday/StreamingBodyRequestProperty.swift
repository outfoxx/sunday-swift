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
