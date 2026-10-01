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

/// A canonical schema validator, including schemas represented by aliases or collections.
public protocol ModelValidator {
  associatedtype Value

  /// Validates current values with shared traversal state and optional diagnostic collection.
  static func isValid(_ value: Value, _ mode: ModelMode, context: inout ModelValidationContext) -> Bool
}

extension ModelValidator {

  /// Checks a value without caching its validity or changing its contents.
  public static func isValid(_ value: Value, _ mode: ModelMode) -> Bool {
    var context = ModelValidationContext()
    return isValid(value, mode, context: &context)
  }

  /// Throws diagnostics collected by one invocation of the canonical implementation.
  public static func validate(_ value: Value, _ mode: ModelMode) throws {
    var context = ModelValidationContext(collectsDiagnostics: true)
    guard isValid(value, mode, context: &context) else {
      throw context.validationError
    }
  }
}
