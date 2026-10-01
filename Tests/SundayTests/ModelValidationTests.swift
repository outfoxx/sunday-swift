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
import Sunday
import Testing

struct ModelValidationTests {

  final class Node: ModelValidatable {
    var stateIsUnknown = false
    var children: [Node] = []
    var validationCalls = 0

    func isValid(_ mode: ModelMode, context: inout ModelValidationContext) -> Bool {
      validationCalls += 1
      return context.withObject(self) { context in
        var valid = true
        if mode == .request && stateIsUnknown {
          valid = context.at(.property("wire-state")) { $0.reject(.unknownEnum) }
          if !context.collectsDiagnostics { return false }
        }
        for (index, child) in children.enumerated() {
          let childValid = context.at(.property("children")) { context in
            context.at(.index(index)) { context in child.isValid(mode, context: &context) }
          }
          if !childValid {
            valid = false
            if !context.collectsDiagnostics { return false }
          }
        }
        return valid
      }
    }
  }

  enum NodeValidator: ModelValidator {
    static func isValid(_ value: Node, _ mode: ModelMode, context: inout ModelValidationContext) -> Bool {
      value.isValid(mode, context: &context)
    }
  }

  @Test func dynamicScalarCapturePreservesNumericStrings() throws {
    struct Capture: Decodable {
      var context: ModelValidationContext
      init(from decoder: Decoder) throws {
        context = try .decoding(decoder, dynamicFields: ["choice"])
      }
    }
    for value in ["0", "false", "1.25"] {
      let payload = try JSONSerialization.data(withJSONObject: ["choice": value])
      var captured = try JSONDecoder().decode(Capture.self, from: payload)
      #expect(captured.context.at(.property("choice")) { context in context.dynamicValue == .string(value) })
    }
    var numeric = try JSONDecoder().decode(Capture.self, from: Data(#"{"choice":0}"#.utf8))
    #expect(numeric.context.at(.property("choice")) { context in
      ModelValidationNumber(value: context.dynamicValue!) == ModelValidationNumber("0")
    })
  }

  @Test func dynamicNumbersPreserveNumericIdentity() {
    #expect(ModelValidationNumber(value: .int64(9_007_199_254_740_993)) == ModelValidationNumber("9007199254740993"))
    let precise = Decimal(string: "0.1234567890123456789")!
    #expect(ModelValidationNumber(value: .decimal(precise)) == ModelValidationNumber("0.1234567890123456789"))
    #expect(ModelValidationNumber(value: .double(0.5)) == ModelValidationNumber("0.5"))
    #expect(ModelValidationNumber(value: .double(.infinity)) == nil)
    #expect(ModelValidationNumber(value: .bool(false)) == nil)
    #expect(ModelValidationNumber(value: .string("12")) == nil)
    #expect(ModelValidationNumber(value: .nil) == nil)
  }

  @Test func numericDescriptionsAndDivisorsRejectMalformedValues() {
    for literal in ["", "nan", "inf", "--1", "1e", "1.2.3", "1e2e3", "1e99999999999999999999999999"] {
      #expect(ModelValidationNumber(validating: literal) == nil)
    }
    #expect(ModelValidationNumber(validating: "-0.00") == ModelValidationNumber("0"))
    #expect(ModelValidationNumber(validating: "1.20e-2") == ModelValidationNumber("0.012"))
    let value = ModelValidationNumber("12")
    #expect(value.isMultipleOf(digits: [0, 3], exponent: 0))
    #expect(ModelValidationNumber("1e1000000000").isMultipleOf(digits: [8], exponent: 0))
    #expect(!ModelValidationNumber("1e1000000000").isMultipleOf(digits: [3], exponent: 0))
    #expect(!ModelValidationNumber("1e-1000000000").isMultipleOf(digits: [1], exponent: 0))
    for input in 0...250 {
      for divisor in 1...50 {
        #expect(ModelValidationNumber(String(input)).isMultipleOf(
          digits: String(divisor).compactMap(\.wholeNumberValue), exponent: 0
        ) == (input % divisor == 0))
      }
    }
    for divisor in [[], [0], [0, 0], [-1], [10]] {
      #expect(!value.isMultipleOf(digits: divisor, exponent: 0))
      #expect(!ModelValidationNumber("0").isMultipleOf(digits: divisor, exponent: 0))
    }
  }

  @Test func unionProbesDoNotLeakFailedAlternatives() {
    var context = ModelValidationContext(collectsDiagnostics: true, validatesNestedModels: false)
    let matched = context.matches { probe in
      #expect(!probe.validatesNestedModels)
      probe.selectAlternative(7)
      return probe.at(.property("alternative")) { $0.reject(.pattern) }
    }
    #expect(!matched)
    #expect(context.diagnostics.isEmpty)
    #expect(context.path.isEmpty)
    #expect(context.selectedAlternative == nil)
    context.selectAlternative(1)
    #expect(context.selectedAlternative == 1)
  }

  @Test func typeAssociatedAPIUsesOneCanonicalInvocation() throws {
    let node = Node()
    #expect(NodeValidator.isValid(node, .request))
    #expect(node.validationCalls == 1)
    node.stateIsUnknown = true
    #expect(throws: ModelValidationError.self) { try NodeValidator.validate(node, .request) }
    #expect(node.validationCalls == 2)
  }

  @Test func decodingRetainsNumericPrecisionAndOriginalCollectionOrder() throws {
    struct Input: Decodable {
      var context: ModelValidationContext
      init(from decoder: Decoder) throws {
        context = try .decoding(decoder, numericFields: ["value", "values"])
      }
    }
    let wire = #"{"value":0.30000000000000000000000000000000000001,"values":[3,3,null,1e200]}"#
    var input = try JSONDecoder().decode(Input.self, from: Data(wire.utf8))
    #expect(!input.context.validatesNestedModels)
    #expect(input.context.at(.property("value")) { context in
      context.number != ModelValidationNumber("0.3")
    })
    #expect(input.context.at(.property("values")) { context in
      context.numberElements == [
        ModelValidationNumber("3"), ModelValidationNumber("3"), nil, ModelValidationNumber("1e200"),
      ]
    })
  }

  @Test func decodingTranslationPreservesTheOriginalDiagnostics() throws {
    var context = ModelValidationContext(collectsDiagnostics: true)
    _ = context.at(.property("samples")) { context in
      context.at(.index(2)) { $0.reject(.multipleOf) }
    }
    guard case .dataCorrupted(let failure) = context.decodingError else {
      Issue.record("Expected a Codable data-corruption error")
      return
    }
    #expect(failure.codingPath.map(\.stringValue) == ["samples", "2"])
    #expect(failure.codingPath.last?.intValue == 2)
    let diagnostic = try #require((failure.underlyingError as? ModelValidationError)?.diagnostics.first)
    #expect(diagnostic.jsonPointer == "/samples/2")
    #expect(diagnostic.reason == .multipleOf)
  }

  @Test func validationDelegatesOnceAndChecksMutation() throws {
    let node = Node()
    try node.validate(.request)
    #expect(node.validationCalls == 1)
    node.stateIsUnknown = true
    #expect(!node.isValid(.request))
    #expect(node.validationCalls == 2)
    #expect(node.isValid(.response))
    #expect(node.validationCalls == 3)
    #expect(throws: ModelValidationError.self) { try node.validate(.request) }
    #expect(node.validationCalls == 4)
  }

  @Test func diagnosticsKeepWirePathsAndTraversalOrder() throws {
    let root = Node()
    let child = Node()
    root.stateIsUnknown = true
    child.stateIsUnknown = true
    root.children = [child, child]
    do {
      try root.validate(.request)
      Issue.record("Expected request validation to fail")
    }
    catch let error as ModelValidationError {
      #expect(error.diagnostics.map(\.jsonPointer) == [
        "/wire-state", "/children/0/wire-state", "/children/1/wire-state",
      ])
      #expect(error.diagnostics.allSatisfy { $0.reason == .unknownEnum })
      #expect(root.validationCalls == 1)
      #expect(child.validationCalls == 2)
    }
  }

  @Test func cyclesFailButSharedReferencesRemainValid() throws {
    let root = Node()
    let child = Node()
    root.children = [child, child]
    try root.validate(.response)
    child.children = [root]
    #expect(throws: ModelValidationError.self) { try root.validate(.response) }
    child.children = []
    try root.validate(.response)
  }

  @Test func presenceAndEscapedMapKeysSurviveAdapters() {
    let field: ModelValidationDiagnostic.PathComponent = .property("optional")
    var context = ModelValidationContext(collectsDiagnostics: true, presence: [[field]: .null])
    #expect(context.presence(of: field, inferred: .omitted) == .null)
    #expect(context.presence(of: .property("absent"), inferred: .omitted) == .omitted)
    _ = context.at(.key("a/b~c")) { $0.reject(.pattern) }
    #expect(context.diagnostics.first?.jsonPointer == "/a~1b~0c")
    #expect(context.path.isEmpty)
  }
}
