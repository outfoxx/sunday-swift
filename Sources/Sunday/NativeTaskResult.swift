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

// Native completion may precede awaiting it. The first result is retained and each waiter resumes once.
final class NativeTaskResult<Value: Sendable>: Sendable {
  private enum State {
    case pending([CheckedContinuation<Value, any Error>])
    case complete(Result<Value, any Error>)
  }
  private let state = Mutex<State>(.pending([]))

  func value() async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      let result = state.withLock { state -> Result<Value, any Error>? in
        switch state {
        case .pending(var waiters):
          waiters.append(continuation)
          state = .pending(waiters)
          return nil
        case .complete(let result): return result
        }
      }
      if let result { continuation.resume(with: result) }
    }
  }

  func complete(_ result: Result<Value, any Error>) {
    let waiters = state.withLock { state -> [CheckedContinuation<Value, any Error>] in
      guard case .pending(let waiters) = state else { return [] }
      state = .complete(result)
      return waiters
    }
    waiters.forEach { $0.resume(with: result) }
  }
}
