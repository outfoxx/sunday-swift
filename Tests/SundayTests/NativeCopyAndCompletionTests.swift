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
@testable import Sunday
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(1)))
struct NativeCopyAndCompletionTests {
  private final class Stop: RequestCancellationError {}

  @Test func requestClonePreservesNativeSettingsAndPrivateMetadata() throws {
    let binding = SecurityBinding(scheme: "key", provider: "key", flow: .static,
                                  transport: .init(location: .header, name: "X-Key"))
    let original = try URLRequest(url: URL(string: "https://example.test/original")!).withSecurity([binding]).clone {
      $0.httpMethod = "POST"
      $0.httpBody = Data("payload".utf8)
      $0.timeoutInterval = 123
      $0.cachePolicy = .reloadIgnoringLocalCacheData
      $0.networkServiceType = .background
      $0.httpShouldHandleCookies = false
      $0.allowsCellularAccess = false
      $0.mainDocumentURL = URL(string: "https://example.test/document")!
    }.setting(header: "X-Test", value: "one")
    let changed = original.clone { $0.url = URL(string: "https://example.test/changed")! }
      .adding(header: "x-test", value: "two")
    #expect(original.url?.path == "/original")
    #expect(original.value(forHTTPHeaderField: "X-Test") == "one")
    #expect(changed.url?.path == "/changed")
    #expect(changed.httpMethod == "POST")
    #expect(changed.httpBody == original.httpBody)
    #expect(changed.timeoutInterval == 123)
    #expect(changed.cachePolicy == original.cachePolicy)
    #expect(changed.networkServiceType == original.networkServiceType)
    #expect(!changed.httpShouldHandleCookies && !changed.allowsCellularAccess)
    #expect(changed.mainDocumentURL == original.mainDocumentURL)
    #expect(changed.securityBindings.count == 1)
    #expect(changed.value(forHTTPHeaderField: "X-Test")?.contains("two") == true)
    #expect(changed.removing(header: "X-TEST").value(forHTTPHeaderField: "x-test") == nil)
  }

  @Test func cloningDoesNotConsumeStreamsAndBodyReplacementClearsOldReplay() throws {
    let factories = Mutex(0)
    let original = try URLRequest(url: URL(string: "https://example.test")!).with(
      streamingBody: StreamingBody(stream: {
        factories.withLock { $0 += 1 }
        return InputStream(data: Data("original".utf8))
      })
    )
    let clone = original.clone { $0.timeoutInterval = 123 }
    #expect(clone.httpBodyStream === original.httpBodyStream)
    #expect(clone.httpBodyStream?.streamStatus == .notOpen)
    #expect(factories.withLock { $0 } == 1)
    let replay = try clone.replayingBody()
    #expect(replay.httpBodyStream !== original.httpBodyStream)
    #expect(factories.withLock { $0 } == 2)
    let replaced = clone.with(httpBody: InputStream(data: Data("replacement".utf8)))
    #expect(replaced.streamingBodyProperty == nil)
    #expect(throws: URLError.self) { try replaced.replayingBody() }
    let buffered = clone.with(httpBody: Data("replacement".utf8))
    #expect(buffered.streamingBodyProperty == nil)
    #expect(buffered.httpBodyStream == nil)
    #expect(original.streamingBodyProperty != nil)
  }

  @Test func responseCloneAndHeaderMutationsPreserveOtherMetadata() throws {
    let original = HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: [
                                     "Content-Type": "application/json", "Content-Length": "7", "X-Test": "one",
                                   ])!
    let changed = try original.clone(statusCode: 202).adding(header: "x-test", value: "two")
    #expect(changed.statusCode == 202)
    #expect(changed.url == original.url)
    #expect(changed.mimeType == original.mimeType)
    #expect(changed.expectedContentLength == original.expectedContentLength)
    #expect(changed.value(forHTTPHeaderField: "X-Test") == "one, two")
    let removed = try changed.removing(header: "X-TEST")
    #expect(removed.value(forHTTPHeaderField: "x-test") == nil)
    #expect(removed.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(original.statusCode == 200)
    #expect(original.value(forHTTPHeaderField: "X-Test") == "one")
    let native: URLResponse = original
    #expect((native.clone() as? HTTPURLResponse)?.statusCode == 200)
    let copy: HTTPURLResponse = original.clone()
    #expect(copy.statusCode == 200)
  }

  @Test func completionBeforeRegistrationRetainsTheFirstError() async {
    let stop = Stop()
    let result = NativeTaskResult<Int>()
    result.complete(.failure(stop))
    result.complete(.success(9))
    do {
      _ = try await result.value()
      Issue.record("Expected the original error")
    }
    catch { #expect((error as? Stop) === stop) }
  }

  @Test func racingWaitersAndCompletionsResumeExactlyOnce() async throws {
    let result = NativeTaskResult<Int>()
    try await withThrowingTaskGroup(of: Int.self) { group in
      for _ in 0 ..< 32 { group.addTask { try await result.value() } }
      result.complete(.success(7))
      result.complete(.success(99))
      var count = 0
      for try await value in group { #expect(value == 7); count += 1 }
      #expect(count == 32)
    }
  }

  @Test(arguments: [false, true])
  func nativeCompletionBeforeHeaderWaitCannotLoseItsResult(cancelled: Bool) async {
    let stop = Stop()
    let session = URLSession(configuration: .ephemeral)
    let request = URLRequest(url: URL(string: "http://127.0.0.1:1")!)
    let attempt = URLSessionRequestAttempt(request: request, delegate: nil)
    let completedTask = session.dataTask(with: request)
    defer { completedTask.cancel(); session.invalidateAndCancel() }
    if cancelled {
      attempt.cancel()
    }
    else { attempt.urlSession(session, task: completedTask, didCompleteWithError: stop) }
    do {
      _ = try await attempt.receiveHeaders(in: session)
      Issue.record("Expected terminal result")
    }
    catch {
      if cancelled {
        #expect(error is CancellationError)
      }
      else { #expect((error as? Stop) === stop) }
    }
    // A second native completion cannot replace the result delivered to the body consumer either.
    attempt.urlSession(session, task: completedTask, didCompleteWithError: URLError(.timedOut))
    do {
      _ = try await attempt.collectBody()
      Issue.record("Expected terminal result")
    }
    catch {
      if cancelled {
        #expect(error is CancellationError)
      }
      else { #expect((error as? Stop) === stop) }
    }
  }
}
