//
//  File.swift
//  
//
//  Created by Kevin Wooten on 5/14/21.
//

import Foundation
import Sunday
import PotentCodables
import PotentJSON
import XCTest


class ProblemTests: XCTestCase {
  
  class TestProblem : Problem {
    
    static let type = URL(string: "http://example.com/test")!
    
    let extra: String
    
    init(extra: String, instance: URL? = nil) {
      self.extra = extra
      super.init(type: Self.type,
                 title: "Test Problem",
                 status: 200,
                 detail: "A Test Problem",
                 instance: instance,
                 parameters: nil)
    }
    
    required init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: AnyCodingKey.self)
      self.extra = try container.decode(String.self, forKey: AnyCodingKey("extra"))      
      try super.init(from: decoder)
    }
    
    override func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: AnyCodingKey.self)
      try container.encode(extra, forKey: AnyCodingKey("extra"))
      try super.encode(to: encoder)
    }
    
  }

  func testCodableForCustomProblems() throws {
    
    let problem = TestProblem(extra: "Some Extra", instance: URL(string: "id:12345"))
    
    let problemJSON = try JSON.Encoder.default.encodeString(problem)
    
    let decodedProblem = try JSON.Decoder.default.decode(TestProblem.self, from: problemJSON)
    
    XCTAssertEqual(problem.type, decodedProblem.type)
    XCTAssertEqual(problem.title, decodedProblem.title)
    XCTAssertEqual(problem.status, decodedProblem.status)
    XCTAssertEqual(problem.detail, decodedProblem.detail)
    XCTAssertEqual(problem.instance, decodedProblem.instance)
    XCTAssertNil(decodedProblem.parameters)
    XCTAssertEqual(problem.extra, decodedProblem.extra)
  }

  func testGenericDecodingForCustomProblems() throws {
    
    let problem = TestProblem(extra: "Some Extra", instance: URL(string: "id:12345"))
    
    let problemJSON = try JSON.Encoder.default.encodeString(problem)
    
    let decodedProblem = try JSON.Decoder.default.decode(Problem.self, from: problemJSON)
    
    XCTAssertEqual(problem.type, decodedProblem.type)
    XCTAssertEqual(problem.title, decodedProblem.title)
    XCTAssertEqual(problem.status, decodedProblem.status)
    XCTAssertEqual(problem.detail, decodedProblem.detail)
    XCTAssertEqual(problem.instance, decodedProblem.instance)
    XCTAssertEqual(["extra": AnyValue.string(problem.extra)], decodedProblem.parameters)
  }

  func testCustomDecodingForGenericProblems() throws {
    
    let customProblem = TestProblem(extra: "Some Extra", instance: URL(string: "id:12345"))
    let genericProblem =
      Problem(
        type: customProblem.type,
        title: customProblem.title,
        status: customProblem.status,
        detail: customProblem.detail,
        instance: customProblem.instance,
        parameters: [
          "extra": AnyValue.string(customProblem.extra)
        ]
      )
    
    let problemJSON = try JSON.Encoder.default.encodeString(genericProblem)
    
    let decodedProblem = try JSON.Decoder.default.decode(TestProblem.self, from: problemJSON)
    
    XCTAssertEqual(customProblem.type, decodedProblem.type)
    XCTAssertEqual(customProblem.title, decodedProblem.title)
    XCTAssertEqual(customProblem.status, decodedProblem.status)
    XCTAssertEqual(customProblem.detail, decodedProblem.detail)
    XCTAssertEqual(customProblem.instance, decodedProblem.instance)
    XCTAssertNil(decodedProblem.parameters)
    XCTAssertEqual(customProblem.extra, decodedProblem.extra)
  }

}
