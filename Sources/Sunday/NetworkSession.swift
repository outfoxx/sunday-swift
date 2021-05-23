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

import Combine
import Foundation


public class NetworkSession {

  internal let session: URLSession
  internal let delegate: NetworkSessionDelegate // swiftlint:disable:this weak_delegate
  internal var taskDelegates: [URLSessionTask: URLSessionTaskDelegate] = [:]
  internal let delegateQueue = OperationQueue()
  internal let serverTrustPolicyManager: ServerTrustPolicyManager?
  internal var closed = false

  public init(
    configuration: URLSessionConfiguration,
    serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
    delegate externalDelegate: URLSessionDelegate? = nil
  ) {
    delegate = NetworkSessionDelegate(delegate: externalDelegate)
    session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
    self.serverTrustPolicyManager = serverTrustPolicyManager
    delegate.owner = self
  }

  public typealias DataTaskPublisher = URLSession.DataTaskPublisher

  public func dataTaskPublisher(for request: URLRequest) -> DataTaskPublisher {
    return session.dataTaskPublisher(for: request)
  }

  public typealias DataTaskValidatedPublisher = AnyPublisher<(response: HTTPURLResponse, data: Data?), Error>

  public func dataTaskValidatedPublisher(request: URLRequest) -> DataTaskValidatedPublisher {
    return dataTaskPublisher(for: request)
      .tryMap { data, response in

        guard let httpResponse = response as? HTTPURLResponse else {
          throw URLError(.badServerResponse)
        }

        if 400 ..< 600 ~= httpResponse.statusCode {
          throw SundayError.responseValidationFailed(reason: .unacceptableStatusCode(
            response: httpResponse,
            data: data
          ))
        }

        return (httpResponse, data)
      }
      .eraseToAnyPublisher()
  }

  public func dataTaskStreamPublisher(for request: URLRequest) -> DataTaskStreamPublisher {
    return DataTaskStreamPublisher(session: self, request: request)
  }

  public func close(cancelOutstandingTasks: Bool) {
    if cancelOutstandingTasks {
      session.invalidateAndCancel()
    }
    else {
      session.finishTasksAndInvalidate()
    }
    closed = true
  }

}
