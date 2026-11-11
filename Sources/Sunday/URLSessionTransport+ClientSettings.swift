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

public extension URLSessionTransport {
  /// Selects standard authentication: attachment, rejection feedback, and cancellation without replay.
  /// Providers are used unchanged; supply TokenManager explicitly for caching and refresh.
  /// The application owns the returned transport and its lifecycle.
  convenience init(
    settings: ClientSettings,
    requestAdapter: (any RequestAdapter)? = nil,
    responseAdapter: (any ResponseAdapter)? = nil,
    serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
    sessionConfiguration: URLSessionConfiguration = .rest(),
    requestQueue: DispatchQueue = .global(qos: .utility),
    mediaTypeEncoders: MediaTypeEncoders = .default,
    mediaTypeDecoders: MediaTypeDecoders = .default
  ) {
    let authentication = StandardAuthenticationAdapter(providers: settings.tokenProviders)
    self.init(
      baseURL: .init(format: settings.baseURL.absoluteString),
      requestAdapter: RequestAdapters([authentication] + (requestAdapter.map { [$0] } ?? [])),
      responseAdapter: ResponseAdapters([authentication] + (responseAdapter.map { [$0] } ?? [])),
      serverTrustPolicyManager: serverTrustPolicyManager,
      sessionConfiguration: sessionConfiguration,
      requestQueue: requestQueue,
      mediaTypeEncoders: mediaTypeEncoders,
      mediaTypeDecoders: mediaTypeDecoders
    )
  }
}
