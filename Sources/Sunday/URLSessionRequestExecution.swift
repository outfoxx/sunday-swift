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

extension URLSession {
  private enum AttemptResult<Body> {
    case next(URLRequest)
    case response(Body, HTTPURLResponse)
  }

  func adaptedData(
    for request: URLRequest, requestAdapter: (any RequestAdapter)?, responseAdapter: (any ResponseAdapter)?
  ) async throws -> (Data, HTTPURLResponse) {
    let (attempt, response) = try await executeAdapted(
      for: request, requestAdapter: requestAdapter, responseAdapter: responseAdapter
    ) { attempt in
      (attempt, try await attempt.receiveHeaders(in: self))
    }
    do {
      return try await (attempt.collectBody(), response)
    }
    catch {
      throw transportError(error, for: attempt)
    }
  }

  func adaptedBytes(
    for request: URLRequest, requestAdapter: (any RequestAdapter)?, responseAdapter: (any ResponseAdapter)?
  ) async throws -> (AsyncBytes, URLResponse) {
    let (bytes, response): (AsyncBytes?, HTTPURLResponse) = try await executeAdapted(
      for: request, requestAdapter: requestAdapter, responseAdapter: responseAdapter
    ) { attempt in
      do {
        let (bytes, response) = try await self.bytes(for: attempt.request, delegate: attempt)
        attempt.attach(task: bytes.task)
        return (bytes, response)
      }
      catch {
        if isRequestCancellation(error) { throw error }
        if Task.isCancelled { throw CancellationError() }
        if let response = attempt.rejectedResponse { return (nil, response) }
        throw error
      }
    }
    if (400 ..< 600).contains(response.statusCode) {
      bytes?.task.cancel()
      throw SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: response, data: nil))
    }
    guard let bytes else { throw URLError(.badServerResponse) }
    return (bytes, response)
  }

  private func executeAdapted<Body>(
    for request: URLRequest, requestAdapter: (any RequestAdapter)?, responseAdapter: (any ResponseAdapter)?,
    send: (URLSessionRequestAttempt) async throws -> (Body, URLResponse)
  ) async throws -> (Body, HTTPURLResponse) {
    var prepared = request
    var redirects = 0
    while true {
      let finalRequest = try await adaptRequest(prepared, using: requestAdapter)
      let attempt = URLSessionRequestAttempt(request: finalRequest, delegate: delegate)
      guard configuration.identifier == nil else { throw URLError(.unsupportedURL) }
      let result: AttemptResult<Body> = try await withTaskCancellationHandler {
        do {
          try Task.checkCancellation()
          let body: Body
          let original: URLResponse
          do {
            (body, original) = try await send(attempt)
          }
          catch {
            throw transportError(error, for: attempt)
          }
          try Task.checkCancellation()
          guard let original = original as? HTTPURLResponse else { throw URLError(.badServerResponse) }
          let response = try await responseAdapter?.adapt(response: original, for: finalRequest) ?? original
          try Task.checkCancellation()
          if !attempt.isolatesCredentials,
             let proposed = redirectedRequest(prepared, sent: finalRequest, response: response),
             let accepted = try await attempt.redirect(in: self, response: response, proposed: proposed) {
            try Task.checkCancellation()
            guard redirects < 20 else { throw URLError(.httpTooManyRedirects) }
            // The delegate owns the whole accepted request, including replacements and native settings.
            var next = accepted.removingObsoleteBodyReplay(comparedTo: proposed)
            if next.httpBodyStream != nil, next.httpBodyStream === prepared.httpBodyStream {
              next = try next.replayingBody()
            }
            redirects += 1
            attempt.cancel()
            return .next(next)
          }
          attempt.acceptBody()
          return .response(body, response)
        }
        catch { attempt.cancel(); throw error }
      } onCancel: { attempt.cancel() }
      switch result {
      case .next(let next): prepared = next
      case .response(let body, let response): return (body, response)
      }
    }
  }

  private func transportError(_ error: any Error, for attempt: URLSessionRequestAttempt) -> any Error {
    if isRequestCancellation(error) { return error }
    // Native replay failures belong to the body installed on this attempt, including adapter replacements.
    if let replayError = attempt.request.streamingBodyProperty?.recordedReplayError { return replayError }
    if Task.isCancelled { return CancellationError() }
    return attempt.isolatesCredentials ? URLError((error as? URLError)?.code ?? .unknown) : error
  }

  private func redirectedRequest(
    _ prepared: URLRequest, sent: URLRequest, response: HTTPURLResponse
  ) -> URLRequest? {
    guard [301, 302, 303, 307, 308].contains(response.statusCode),
          let location = response.value(forHTTPHeaderField: "Location"),
          let url = URL(string: location, relativeTo: response.url)?.absoluteURL else { return nil }
    let method = sent.httpMethod ?? "GET"
    let becomesGet = (response.statusCode == 303 && method != "HEAD") ||
      ([301, 302].contains(response.statusCode) && method == "POST")
    return prepared.clone {
      $0.url = url
      $0.httpMethod = becomesGet ? "GET" : method
      if becomesGet {
        $0.httpBody = nil
        $0.httpBodyStream = nil
        $0.setValue(nil, forHTTPHeaderField: "Content-Type")
        $0.setValue(nil, forHTTPHeaderField: "Content-Length")
        $0.setValue(nil, forHTTPHeaderField: "Transfer-Encoding")
      }
    }
  }
}
