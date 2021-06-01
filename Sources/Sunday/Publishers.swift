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


public typealias RequestPublisher = AnyPublisher<URLRequest, Error>
public typealias RequestResponsePublisher = AnyPublisher<(response: HTTPURLResponse, data: Data?), Error>
public typealias RequestResultPublisher<T> = AnyPublisher<T, Error>
public typealias RequestCompletePublisher = RequestResultPublisher<Void>
public typealias RequestEventPublisher<E> = AnyPublisher<E, Error>



public extension RequestResultPublisher {

  func nilifyResponse(
    statusCodes: [HTTP.StatusCode],
    problemTypes: [Problem.Type] = []
  ) -> AnyPublisher<Output?, Error> {
    return nilifyResponse(statuses: statusCodes.map(\.rawValue), problemTypes: problemTypes)
  }

  func nilifyResponse(statuses: [Int] = [404], problemTypes: [Problem.Type] = []) -> AnyPublisher<Output?, Error> {
    return map { $0 as Output? }
      .tryCatch { (error: Error) throws -> Just<Output?> in

        guard
          let problem = error as? Problem,
          statuses.contains(problem.status) || problemTypes.contains(where: { $0 == type(of: error) })
        else {
          throw error
        }

        return Just(nil)
      }
      .eraseToAnyPublisher()
  }

}
