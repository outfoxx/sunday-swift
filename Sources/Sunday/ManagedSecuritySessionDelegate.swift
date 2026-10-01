/*
 * Copyright 2026 Outfox, Inc.
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

// Credentials must not be replayed by URLSession independently of the invocation recovery budget.
final class ManagedSecuritySessionDelegate: NSObject, URLSessionTaskDelegate {
  let rejectedResponse = Mutex<HTTPURLResponse?>(nil)
  private let delegate: (any URLSessionDelegate)?
  init(delegate: (any URLSessionDelegate)?) { self.delegate = delegate }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? { nil }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?)
      -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
      // Other dispositions can make URLSession replay even with a nil credential. Cancel that
      // native authentication attempt and retain its HTTP status for the invocation owner.
      rejectedResponse.withLock { $0 = challenge.failureResponse as? HTTPURLResponse }
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    if let delegate = delegate as? any URLSessionTaskDelegate,
       delegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:))) {
      delegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }
    else if let delegate,
            delegate.responds(to: #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))) {
      delegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
    }
    else { completionHandler(.performDefaultHandling, nil) }
  }
}
