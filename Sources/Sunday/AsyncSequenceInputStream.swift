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


enum AsyncSequenceInputStream {

  static func makeInputStream<S>(
    bytes: S
  ) throws -> InputStream where S: AsyncSequence & Sendable, S.Element == Data {

    var inputStream: InputStream?
    var outputStream: OutputStream?
    Stream.getBoundStreams(
      withBufferSize: 64 * 1024,
      inputStream: &inputStream,
      outputStream: &outputStream
    )

    guard let inputStream, let outputStream else {
      throw SundayError.requestEncodingFailed(reason: .streamCreationFailed)
    }

    let owner = AsyncSequenceInputStreamOwner(outputStream: outputStream, bytes: bytes)

    return RetainedInputStream(inputStream: inputStream, owner: owner)
  }

}


// OutputStream is not Sendable, but this owner keeps it private to one writer task and only exposes cancellation.
private final class AsyncSequenceInputStreamOwner<S>: NSObject, StreamDelegate, @unchecked Sendable where S: AsyncSequence & Sendable, S.Element == Data {

  private enum State: Sendable {
    case idle
    case running(Task<Void, Never>, CheckedContinuation<Void, any Error>?)
    case closed
  }

  private final class RunLoopReference: @unchecked Sendable {

    let value: CFRunLoop

    init(_ value: CFRunLoop) {
      self.value = value
    }

  }

  private let outputStream: OutputStream
  private let bytes: S
  private let state = Mutex(State.idle)
  private let runLoop = Mutex<RunLoopReference?>(nil)

  init(outputStream: OutputStream, bytes: S) {
    self.outputStream = outputStream
    self.bytes = bytes
    super.init()
  }

  func start() {
    let task = Task.detached { [self] in
      await startRunLoop()

      guard !Task.isCancelled, !isClosed else {
        return
      }

      outputStream.open()
      defer { close(cancelTask: false) }

      do {
        for try await chunk in bytes {
          try await write(chunk)
          if Task.isCancelled {
            return
          }
        }
      }
      catch {
        return
      }
    }

    state.withLock { state in
      switch state {
      case .idle:
        state = .running(task, nil)
      case .running:
        task.cancel()
      case .closed:
        task.cancel()
      }
    }
  }

  func cancel() {
    close(cancelTask: true)
  }

  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .hasSpaceAvailable:
      resumeWaitingWriter()
    case .errorOccurred, .endEncountered:
      resumeWaitingWriter(throwing: outputStream.streamError ?? SundayError.requestEncodingFailed(reason: .streamCreationFailed))
    default:
      break
    }
  }

  private func write(_ data: Data) async throws {
    var remaining = data.count
    var offset = 0

    while remaining > 0 {
      let written =
        data.withUnsafeBytes { bytes in
          guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
            return 0
          }

          return outputStream.write(baseAddress + offset, maxLength: remaining)
        }

      if written > 0 {
        offset += written
        remaining -= written
      }
      else if written == 0 {
        try await waitForSpace()
      }
      else {
        throw outputStream.streamError ?? SundayError.requestEncodingFailed(reason: .streamCreationFailed)
      }
    }
  }

  private func waitForSpace() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let immediateResult: Result<Void, any Error>? =
          state.withLock { state in
            switch state {
            case .idle, .closed:
              return .failure(CancellationError())
            case .running(_, .some):
              return .failure(SundayError.requestEncodingFailed(reason: .streamCreationFailed))
            case .running(let task, nil):
              if outputStream.hasSpaceAvailable {
                return .success(())
              }
              state = .running(task, continuation)
              return nil
            }
          }

        if let immediateResult {
          continuation.resume(with: immediateResult)
        }
      }
    } onCancel: {
      resumeWaitingWriter(throwing: CancellationError())
    }
  }

  private func resumeWaitingWriter(throwing error: (any Error)? = nil) {
    let continuation =
      state.withLock { state -> CheckedContinuation<Void, any Error>? in
        switch state {
        case .idle, .closed:
          return nil
        case .running(_, nil):
          return nil
        case .running(let task, .some(let continuation)):
          state = .running(task, nil)
          return continuation
        }
      }

    if let error {
      continuation?.resume(throwing: error)
    }
    else {
      continuation?.resume()
    }
  }

  private func startRunLoop() async {
    await withCheckedContinuation { continuation in
      Thread.detachNewThread { [self] in
        runLoop.withLock { runLoop in
          runLoop = RunLoopReference(CFRunLoopGetCurrent())
        }

        outputStream.delegate = self
        outputStream.schedule(in: .current, forMode: .default)
        continuation.resume()

        while !isClosed {
          CFRunLoopRun()
        }

        outputStream.remove(from: .current, forMode: .default)
        outputStream.delegate = nil
      }
    }
  }

  private func close(cancelTask: Bool) {
    let continuation =
      state.withLock { state -> CheckedContinuation<Void, any Error>? in
        switch state {
        case .idle:
          state = .closed
          outputStream.close()
          return nil
        case .running(let task, let continuation):
          if cancelTask {
            task.cancel()
          }
          state = .closed
          outputStream.close()
          return continuation
        case .closed:
          return nil
        }
      }

    continuation?.resume(throwing: CancellationError())

    if let runLoop = runLoop.withLock({ $0 }) {
      CFRunLoopStop(runLoop.value)
    }
  }

  private var isClosed: Bool {
    state.withLock { state in
      if case .closed = state {
        return true
      }
      return false
    }
  }

  deinit {
    cancel()
  }

}


private final class RetainedInputStream: InputStream, @unchecked Sendable {

  private let inputStream: InputStream
  private let startOwner: @Sendable () -> Void
  private let cancelOwner: @Sendable () -> Void

  init<S>(inputStream: InputStream, owner: AsyncSequenceInputStreamOwner<S>) {
    self.inputStream = inputStream
    self.startOwner = { owner.start() }
    self.cancelOwner = { owner.cancel() }
    super.init(data: Data())
  }

  override var streamStatus: Stream.Status {
    inputStream.streamStatus
  }

  override var streamError: (any Error)? {
    inputStream.streamError
  }

  override var hasBytesAvailable: Bool {
    inputStream.hasBytesAvailable
  }

  override var delegate: (any StreamDelegate)? {
    get {
      inputStream.delegate
    }
    set {
      inputStream.delegate = newValue
    }
  }

  override func open() {
    inputStream.open()
    startOwner()
  }

  override func close() {
    cancelOwner()
    inputStream.close()
  }

  override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
    inputStream.read(buffer, maxLength: len)
  }

  override func getBuffer(
    _ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
    length len: UnsafeMutablePointer<Int>
  ) -> Bool {
    inputStream.getBuffer(buffer, length: len)
  }

  override func property(forKey key: Stream.PropertyKey) -> Any? {
    inputStream.property(forKey: key)
  }

  override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
    inputStream.setProperty(property, forKey: key)
  }

  override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
    inputStream.schedule(in: aRunLoop, forMode: mode)
  }

  override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
    inputStream.remove(from: aRunLoop, forMode: mode)
  }

  deinit {
    cancelOwner()
  }

}
