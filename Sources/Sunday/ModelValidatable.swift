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

/// A model that delegates validation to its generated, type-associated implementation.
public protocol ModelValidatable {
  /// Runs the canonical validator once using the caller's traversal and diagnostic state.
  func isValid(_ mode: ModelMode, context: inout ModelValidationContext) -> Bool
}

extension ModelValidatable {

  /// Checks the model's current values, stopping at the first failure when possible.
  public func isValid(_ mode: ModelMode) -> Bool {
    var context = ModelValidationContext()
    return isValid(mode, context: &context)
  }

  /// Collects failures during a single canonical validation pass and throws if invalid.
  public func validate(_ mode: ModelMode) throws {
    var context = ModelValidationContext(collectsDiagnostics: true)
    guard isValid(mode, context: &context) else {
      throw context.validationError
    }
  }
}
