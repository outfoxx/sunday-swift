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

import XCTest


public func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "did not throw an error",
  _ file: StaticString = #file,
  _ line: UInt = #line,
  _ errorHandler: (Error) -> Void = { _ in /* do nothing */ }
) async throws {
  do {
    _ = try await expression()
    XCTFail("XCTAssertThrowsError failed: \(message())", file: file, line: line)
  }
  catch {
    errorHandler(error)
  }
}
