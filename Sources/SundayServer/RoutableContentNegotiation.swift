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

//  swiftlint:disable identifier_name

import Foundation
import Sunday


/// Utility to set `RequestDecoding` and `ResponseEncoding` as negotiated based on
/// `Content-Type` and `Accept` headers.
///
public func ContentNegotiation(
  decoders: MediaTypeDecoders = .default,
  encoders: MediaTypeEncoders = .default,
  @RoutableBuilder buildRoutable: () -> Routable
) -> Routable {
  RequestDecoding(scheme: .negotiated, decoders: decoders) {
    ResponseEncoding(scheme: .negotiated, encoders: encoders, buildRoutable: buildRoutable)
  }
}
