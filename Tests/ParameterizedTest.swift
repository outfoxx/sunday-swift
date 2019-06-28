//
//  ParameterizedTest.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/10/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import XCTest


class ParameterizedTest: XCTestCase {

  override class var defaultTestSuite : XCTestSuite {
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

  open class var parameterSets : [Any] {
    return []
  }

  open func setUp(with parameters: Any) {
  }

}
