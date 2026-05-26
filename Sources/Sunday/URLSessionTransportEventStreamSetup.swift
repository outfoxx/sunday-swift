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
import OSLog


private let eventStreamLogger = Logger.for(category: "Event Streams")


private struct URLSessionTransportEventStreamSetupState: Sendable {
  var isTerminated = false
  var task: Task<Void, Never>?
}


final class URLSessionTransportEventStreamSetup: Sendable {

  private let state = Mutex(URLSessionTransportEventStreamSetupState())

  var isTerminated: Bool {
    state.withLock { $0.isTerminated }
  }

  func store(task: Task<Void, Never>) {
    let shouldCancelTask =
      state.withLock { state in
        guard !state.isTerminated else {
          return true
        }

        state.task = task
        return false
      }

    if shouldCancelTask {
      task.cancel()
    }
  }

  func terminate() -> Task<Void, Never>? {
    state.withLock { state in
      state.isTerminated = true
      defer { state.task = nil }
      return state.task
    }
  }

  func start<D>(
    eventSource: EventSource,
    continuation: AsyncStream<D>.Continuation,
    shouldCancel: @escaping @Sendable () -> Bool,
    jsonDecoder: TextMediaTypeDecoder,
    decoder: @escaping @Sendable (TextMediaTypeDecoder, String?, String?, String, Logger) throws -> D?
  ) -> Task<Void, Never> {
    Task {
      let shouldStop: @Sendable () -> Bool = {
        Task.isCancelled || self.isTerminated || shouldCancel()
      }

      guard !shouldStop() else {
        continuation.finish()
        return
      }

      await eventSource.setOnStateError { _, readyState in
        if readyState == .closed {
          continuation.finish()
        }
      }

      guard !shouldStop() else {
        continuation.finish()
        return
      }

      await eventSource.setOnMessage { event, id, data in
        guard let data else {
          return
        }

        do {
          guard let event = try decoder(jsonDecoder, event, id, data, eventStreamLogger) else {
            return
          }

          continuation.yield(event)
        }
        catch {
          eventStreamLogger.error("Unable to decode event: \(error.localizedDescription, privacy: .public)")
        }
      }

      await eventSource.connect(unless: shouldStop)

      if shouldStop() {
        await eventSource.close()
        continuation.finish()
      }
    }
  }
}
