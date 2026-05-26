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


/// A type-erased problem registration that can be shared across generated service clients.
public struct ProblemRegistration: Sendable {

  /// The registered RFC 9457 problem type URI.
  public let type: String

  private let registerProblem: @Sendable (any Transport) -> Void

  /// Creates a problem registration for the given problem type URI.
  public init<P: Problem>(type: URL, problemType: P.Type) {
    self.init(type: type.absoluteString, problemType: problemType)
  }

  /// Creates a problem registration for the given problem type URI.
  public init<P: Problem>(type: String, problemType: P.Type) {
    self.type = type
    self.registerProblem = { transport in
      transport.registerProblem(type: type, problemType: problemType)
    }
  }

  /// Registers the problem with the provided transport.
  public func register(on transport: any Transport) {
    registerProblem(transport)
  }

}
