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


public extension URLSession {

  static func sunday(
    configuration: URLSessionConfiguration,
    serverTrustPolicyManager: ServerTrustPolicyManager? = nil
  ) -> URLSession {
    return URLSession(
      configuration: configuration,
      delegate: SundayURLSessionDelegate(serverTrustPolicyManager: serverTrustPolicyManager),
      delegateQueue: nil
    )
  }

  func validatedData(for request: URLRequest) async throws -> (Data?, HTTPURLResponse) {

    let responseBody: Data
    let response: URLResponse
    do {
      (responseBody, response) = try await data(for: request)
    }
    catch {
      if let replayError = request.streamingBodyRequestProperty?.recordedReplayError {
        throw replayError
      }
      throw error
    }

    return try validate(responseBody: responseBody, response: response)
  }

  private func validate(responseBody: Data, response: URLResponse) throws -> (Data?, HTTPURLResponse) {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    let responseData = responseBody.isEmpty ? nil : responseBody

    if 400 ..< 600 ~= httpResponse.statusCode {
      throw SundayError.responseValidationFailed(reason: .unacceptableStatusCode(
        response: httpResponse,
        data: responseData
      ))
    }

    return (responseData, httpResponse)
  }

  enum DataEvent {
    case connect(HTTPURLResponse)
    case data(Data)
  }

  struct DataEventStream: AsyncSequence {

    public typealias Element = DataEvent
    public typealias Failure = Error

    private enum Source {
      case request(URLSession, URLRequest)
      case events(AsyncThrowingStream<DataEvent, Error>)
    }

    private enum IteratorState {
      case pending(URLSession, URLRequest)
      case streaming(URLSession.AsyncBytes.AsyncIterator, DataEventBuffer)
      case events(AsyncThrowingStream<DataEvent, Error>.Iterator)
      case finished
    }

    public struct AsyncIterator: AsyncIteratorProtocol {

      private var state: IteratorState

      init(session: URLSession, request: URLRequest) {
        state = .pending(session, request)
      }

      init(events: AsyncThrowingStream<DataEvent, Error>) {
        state = .events(events.makeAsyncIterator())
      }

      public mutating func next() async throws -> DataEvent? {
        switch state {
        case .pending(let session, let request):
          guard !Task.isCancelled else {
            state = .finished
            return nil
          }

          let (bytes, response) = try await session.bytes(for: request)

          guard let httpResponse = response as? HTTPURLResponse else {
            throw SundayError.invalidHTTPResponse
          }

          if 400 ..< 600 ~= httpResponse.statusCode {
            throw SundayError.responseValidationFailed(reason: .unacceptableStatusCode(
              response: httpResponse,
              data: nil
            ))
          }

          state = .streaming(bytes.makeAsyncIterator(), DataEventBuffer(response: httpResponse))
          return .connect(httpResponse)

        case .streaming(var byteIterator, var buffer):
          guard !Task.isCancelled else {
            state = .finished
            return nil
          }

          while let byte = try await byteIterator.next() {
            if let data = buffer.append(byte) {
              state = .streaming(byteIterator, buffer)
              return .data(data)
            }
          }

          state = .finished

          if let data = buffer.finish() {
            return .data(data)
          }

          return nil

        case .events(var iterator):
          guard let event = try await iterator.next() else {
            state = .finished
            return nil
          }

          state = .events(iterator)
          return event

        case .finished:
          return nil
        }
      }

    }

    private let source: Source

    init(session: URLSession, request: URLRequest) {
      self.source = .request(session, request)
    }

    init(events: AsyncThrowingStream<DataEvent, Error>) {
      self.source = .events(events)
    }

    public func makeAsyncIterator() -> AsyncIterator {
      switch source {
      case .request(let session, let request):
        AsyncIterator(session: session, request: request)
      case .events(let events):
        AsyncIterator(events: events)
      }
    }

  }

  func dataEventStream(for request: URLRequest) throws -> DataEventStream {
    DataEventStream(session: self, request: request)
  }

  func close(cancelOutstandingTasks: Bool) {
    if cancelOutstandingTasks {
      invalidateAndCancel()
    }
    else {
      finishTasksAndInvalidate()
    }
  }

}


struct DataEventBuffer {

  private static let maximumBufferedBytes = 4096

  private let responseIsEventStream: Bool
  private var data = Data(capacity: maximumBufferedBytes)
  private var previousByte: UInt8?
  private var previousPreviousByte: UInt8?

  init(response: HTTPURLResponse) {
    switch response.value(forHTTPHeaderField: HTTP.StdHeaders.contentType) ?? "" {
    case MediaType.eventStream:
      self.responseIsEventStream = true
    default:
      self.responseIsEventStream = false
    }
  }

  mutating func append(_ byte: UInt8) -> Data? {
    data.append(byte)

    guard responseIsEventStream else {
      return flush(resetBoundaryState: true)
    }

    if isEventBoundary(byte) {
      return flush(resetBoundaryState: true)
    }

    if data.count >= Self.maximumBufferedBytes {
      let chunk = flush(resetBoundaryState: false)
      previousPreviousByte = previousByte
      previousByte = byte
      return chunk
    }

    previousPreviousByte = previousByte
    previousByte = byte
    return nil
  }

  mutating func finish() -> Data? {
    flush(resetBoundaryState: true)
  }

  private func isEventBoundary(_ byte: UInt8) -> Bool {
    switch (previousPreviousByte, previousByte, byte) {
    case (_, .some(0x0A), 0x0A):
      return true
    case (_, .some(0x0D), 0x0D):
      return true
    case (.some(0x0A), .some(0x0D), 0x0A):
      return true
    default:
      return false
    }
  }

  private mutating func flush(resetBoundaryState: Bool) -> Data? {
    guard !data.isEmpty else {
      return nil
    }

    defer {
      data.removeAll(keepingCapacity: true)
      if resetBoundaryState {
        previousByte = nil
        previousPreviousByte = nil
      }
    }
    return data
  }

}


private final class SundayURLSessionDelegate: NSObject, URLSessionTaskDelegate {

  private let serverTrustPolicyManager: ServerTrustPolicyManager?

  init(serverTrustPolicyManager: ServerTrustPolicyManager?) {
    self.serverTrustPolicyManager = serverTrustPolicyManager
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void
  ) {
    guard
      let request = task.currentRequest ?? task.originalRequest,
      let property = URLProtocol.property(
        forKey: streamingBodyRequestPropertyKey,
        in: request
      ) as? StreamingBodyRequestProperty
    else {
      completionHandler(nil)
      return
    }

    do {
      completionHandler(try property.body.makeInputStream())
    }
    catch {
      property.recordReplayError(error)
      task.cancel()
      completionHandler(nil)
    }
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let serverTrustPolicyManager,
      let serverTrustPolicy = serverTrustPolicyManager.serverTrustPolicy(forHost: challenge.protectionSpace.host),
      let serverTrust = challenge.protectionSpace.serverTrust
    else {
      return completionHandler(.performDefaultHandling, nil)
    }

    if serverTrustPolicy.evaluate(serverTrust, forHost: challenge.protectionSpace.host) {
      completionHandler(.useCredential, URLCredential(trust: serverTrust))
      return
    }

    completionHandler(.cancelAuthenticationChallenge, nil)
  }

}


private extension URLRequest {

  var streamingBodyRequestProperty: StreamingBodyRequestProperty? {
    URLProtocol.property(
      forKey: streamingBodyRequestPropertyKey,
      in: self
    ) as? StreamingBodyRequestProperty
  }

}
