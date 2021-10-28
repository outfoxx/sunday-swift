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


public func nilifyResponse<R>(
  statusCodes: [HTTP.StatusCode],
  problemTypes: [Problem.Type] = [],
  block: () async throws -> R
) async throws -> R? {
  return try await nilifyResponse(statuses: statusCodes.map(\.rawValue), problemTypes: problemTypes, block: block)
}

public func nilifyResponse<R>(
  statuses: [Int] = [404],
  problemTypes: [Problem.Type] = [],
  block: () async throws -> R
) async throws -> R? {
  do {
    return try await block()
  }
  catch {
    guard
      let problem = error as? Problem,
      statuses.contains(problem.status) || problemTypes.contains(where: { $0 == type(of: error) })
    else {
      throw error
    }
    return nil
  }
}
