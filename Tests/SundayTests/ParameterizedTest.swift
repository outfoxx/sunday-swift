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


class ParameterizedTest: XCTestCase {

  override class var defaultTestSuite: XCTestSuite {
    let testSuite = XCTestSuite(forTestCaseClass: self)
    parameterSets.forEach { parameterSet in
      testInvocations.forEach { invocation in
        let testClass = NSClassFromString(NSStringFromClass(self)) as! XCTestCase.Type
        let testCase = testClass.init(invocation: invocation) as! ParameterizedTest
        testCase.setUp(with: parameterSet)
        testSuite.addTest(testCase)
      }
    }
    return testSuite
  }

  open class var parameterSets: [Any] {
    return []
  }

  open func setUp(with parameters: Any) {}

}
