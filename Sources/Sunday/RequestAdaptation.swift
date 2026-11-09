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

// Credential receipts belong to the attempt. Body replay factories belong to the stream they created.
func adaptRequest(_ request: URLRequest, using adapter: (any RequestAdapter)?) async throws -> URLRequest {
  try Task.checkCancellation()
  var result = try await adapter?.adapt(request: request) ?? request
  try Task.checkCancellation()
  if result.securityProperty == nil, let context = request.securityProperty {
    result = try result.withSecurity(context.bindings, leases: context.leases)
  }
  return result.removingObsoleteBodyReplay(comparedTo: request)
}
