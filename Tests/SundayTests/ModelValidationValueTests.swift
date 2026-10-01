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
import PotentJSON
import Sunday
import Testing

struct ModelValidationValueTests {
  private enum ParentSchema {}
  private enum ChildSchema {}
  private enum IndependentSchema {}

  @Test func nestedDelegationKeepsIndependentSchemasAndSkipsOnlyPreviouslyDecodedSchemas() {
    var projectedCalls = 0, declaredCalls = 0
    let value = ModelValidationValue.object(schemas: [ParentSchema.self, ChildSchema.self], validate: { _, _ in
      projectedCalls += 1
      return true
    }, fields: { [:] })
    #expect(value.hasProjectedSchema)
    #expect(value.represents(ChildSchema.self))
    #expect(!value.represents(IndependentSchema.self))
    #expect(!(ModelValidationValue.object { [:] }).hasProjectedSchema)
    let independent: ModelObjectValidation.Validator = { _, _, context in
      declaredCalls += 1
      return context.reject(.maxItems)
    }
    for nested in [true, false] {
      var context = ModelValidationContext(collectsDiagnostics: true, validatesNestedModels: nested)
      #expect(value.validateNested(.request, schema: ParentSchema.self, context: &context, declared: independent))
      #expect(!value.validateNested(.request, schema: IndependentSchema.self, context: &context, declared: independent))
      #expect(context.diagnostics.map(\.reason) == [.maxItems])
    }
    #expect(projectedCalls == 1)
    #expect(declaredCalls == 2)
  }

  private final class Node {
    var visits = 0
    var children: [Node] = []
    var view: ModelValidationValue {
      .object(identity: self) {
        self.visits += 1
        return ["children": .array { self.children.map(\.view) }]
      }
    }
  }

  @Test func projectionIsLazyAndObservesCurrentValues() {
    let node = Node()
    let view = node.view
    #expect(node.visits == 0)
    let child = Node()
    node.children = [child, child]
    #expect(view.fields?["children"]?.elements?.count == 2)
    #expect(node.visits == 1)
    #expect(child.visits == 0)
    node.children.removeLast()
    #expect(view.fields?["children"]?.elements?.count == 1)
  }

  @Test func structuralEqualityPreservesWireIdentityAndNumericPrecision() {
    #expect(ModelValidationValue.number("1.0").equivalent(to: .number("1")))
    #expect(!ModelValidationValue.number("9007199254740993").equivalent(to: .number("9007199254740992")))
    #expect(!ModelValidationValue.string("1").equivalent(to: .number("1")))
    #expect(!ModelValidationValue.boolean(false).equivalent(to: .number("0")))
    #expect(!ModelValidationValue.null.equivalent(to: .omitted))
    #expect(ModelValidationValue(.string("12")).kind == .string)
    #expect(ModelValidationValue(.double(.infinity)).kind == .invalid)
    let fields: ModelValidationValue = .object { ["absent": .omitted, "value": .null] }
    #expect(fields.equivalent(to: .object { ["value": .null] }))
    #expect(!fields.equivalent(to: .object { [:] }))
  }

  @Test func cyclesTerminateAndSharedReferencesRemainValid() {
    let node = Node(), leaf = Node()
    node.children = [leaf, leaf]
    #expect(node.view.equivalent(to: node.view))
    node.children = [node]
    #expect(!node.view.equivalent(to: node.view))
    var context = ModelValidationContext(collectsDiagnostics: true)
    let view = node.view
    #expect(!view.validating(context: &context) { context in
      context.at(.property("children")) { context in
        context.at(.index(0)) { context in
          view.fields!["children"]!.elements![0].validating(context: &context) { _ in true }
        }
      }
    })
    #expect(context.diagnostics.first?.reason == .cycle)
    #expect(context.diagnostics.first?.jsonPointer == "/children/0")
    node.children = [leaf]
    #expect(view.validating(context: &context) { _ in true })
  }

  @Test func sharedAssertionsCollectStableDiagnosticsWithoutASecondTraversal() {
    let rules = ModelValueConstraints([
      .allowedValues([.number("2")]), .minimum(.init("3")), .maximum(.init("0")),
      .multipleOf(digits: [2], exponent: 0),
    ])
    var context = ModelValidationContext(collectsDiagnostics: true)
    #expect(!context.at(.property("wire-count")) { context in
      rules.isValid(.number("1"), context: &context)
    })
    #expect(context.diagnostics.map(\.reason) == [.allowedValue, .minimum, .maximum, .multipleOf])
    #expect(context.diagnostics.allSatisfy { $0.jsonPointer == "/wire-count" })
    var shortCircuit = ModelValidationContext()
    #expect(!rules.isValid(.number("1"), context: &shortCircuit))
    #expect(shortCircuit.diagnostics.isEmpty)
    let unicode = ModelValueConstraints([.minLength(2), .maxLength(2), .pattern("^e")])
    #expect(unicode.isValid(.string("e\u{301}"), context: &shortCircuit))
    #expect(!unicode.isValid(.string("é"), context: &shortCircuit))
  }

  @Test func elementAssertionsRetainNullableItemsAndIndexedDiagnostics() {
    let rules = ModelValueConstraints([.minItems(1)]).appending(.elements(
      ModelValueConstraints([.minimum(.init("2")), .multipleOf(digits: [2], exponent: 0)]), nullable: true
    ))
    var context = ModelValidationContext(collectsDiagnostics: true)
    #expect(rules.isValid(.array { [.number("2"), .null, .number("4")] }, context: &context))
    #expect(!rules.isValid(.array { [.number("1"), .null, .number("3")] }, context: &context))
    #expect(context.diagnostics.map(\.reason) == [.minimum, .multipleOf, .multipleOf])
    #expect(context.diagnostics.map(\.jsonPointer) == ["/0", "/0", "/2"])
  }

  @Test func uniqueItemsCompareObjectsWithoutInvokingTheirConstructorsOrHashingCycles() {
    let rules = ModelValueConstraints([.minItems(1), .maxItems(2), .uniqueItems])
    let node = Node(), other = Node()
    var context = ModelValidationContext()
    #expect(!rules.isValid(.array { [node.view, other.view] }, context: &context))
    other.children = [Node()]
    #expect(rules.isValid(.array { [node.view, other.view] }, context: &context))
    node.children = [node]
    #expect(rules.isValid(.array { [node.view, node.view] }, context: &context))
    // The separate object traversal rejects the cycle; equality must merely terminate.
  }


  @Test func objectFieldsAndPatternsShareDirectionAndTraverseOnlyOnce() {
    var calls: [String] = []
    let text = ModelValueConstraints([.minLength(2)])
    let schema = ModelObjectValidation(
      fields: [
        .init("wire-name", required: true) { value, mode, context in
          calls.append("name-\(mode)")
          return text.isValid(value, context: &context)
        },
      ],
      patterns: [
        .init("^x-") { value, mode, context in
          calls.append("x-\(mode)")
          return text.isValid(value, context: &context)
        },
        .init("end$") { value, mode, context in
          calls.append("end-\(mode)")
          return ModelValueConstraints([.pattern("^ok")]).isValid(value, context: &context)
        },
      ],
      closed: true
    )
    var context = ModelValidationContext(collectsDiagnostics: true)
    let value: ModelValidationValue = .object {
      ["wire-name": .string("a"), "x-end": .string("x"), "extra": .null]
    }
    #expect(!schema.isValid(value, .request, context: &context))
    #expect(calls == ["name-request", "x-request", "end-request"])
    #expect(context.diagnostics.map(\.jsonPointer) == ["/wire-name", "/extra", "/x-end", "/x-end"])
    #expect(context.diagnostics.map(\.reason) == [.minLength, .additionalProperty, .minLength, .pattern])
    calls.removeAll()
    var shortCircuit = ModelValidationContext()
    #expect(!schema.isValid(value, .response, context: &shortCircuit))
    #expect(calls == ["name-response"])
  }


  @Test func stringFormatsCheckNativePrimitiveSyntax() {
    let cases: [(ModelStringFormat, (accepted: String, rejected: String))] = [
      (.uuid, ("E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "not-a-uuid")),
      (.url, ("https://example.com/path", "http://[invalid")),
      (.base64, ("YWJj", "not-base64")),
      (.date, ("2026-09-30", "2026-09-30suffix")),
      (.time, ("12:34:56.123", "12:34")),
      (.dateTime, ("2026-09-30T12:34:56.123+01:00", "2026-09-30T12:34:56")),
      (.localDateTime, ("2026-09-30T12:34:56", "2026-09-30T12:34:56Z")),
    ]
    for (format, values) in cases {
      let (accepted, rejected) = values
      var context = ModelValidationContext(collectsDiagnostics: true)
      #expect(format.isValid(.string(accepted), context: &context), "Expected valid format: \(accepted)")
      #expect(!context.at(.key("wire-value")) { context in
        format.isValid(.string(rejected), context: &context)
      })
      #expect(context.diagnostics.map(\.jsonPointer) == ["/wire-value"])
      #expect(context.diagnostics.map(\.reason) == [.invalidValue])
    }
  }

  @Test func stringDatesRespectCalendarBoundariesAndCaseInsensitiveSeparators() {
    var context = ModelValidationContext()
    for value in ["2024-02-29", "2000-02-29", "2026-04-30"] {
      #expect(ModelStringFormat.date.isValid(.string(value), context: &context))
    }
    for value in ["2026-02-29", "1900-02-29", "2026-04-31", "2026-00-01", "2026-01-00"] {
      #expect(!ModelStringFormat.date.isValid(.string(value), context: &context))
      #expect(!ModelStringFormat.dateTime.isValid(.string(value + "T12:00:00Z"), context: &context))
    }
    #expect(ModelStringFormat.dateTime.isValid(.string("2026-09-30t12:34:56z"), context: &context))
    #expect(ModelStringFormat.localDateTime.isValid(.string("2026-09-30t12:34:56"), context: &context))
  }

  @Test func scalarCaptureRetainsNumbersBeforeStorageRounding() throws {
    struct Scalar: Decodable {
      let value: Double
      let context: ModelValidationContext
      init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(Double.self)
        context = try .decodingValue(decoder)
      }
    }
    let scalar = try Foundation.JSONDecoder().decode(Scalar.self, from: Data("1.00000000000000000001".utf8))
    #expect(scalar.value == 1)
    #expect(scalar.context.originalValue?.number == ModelValidationNumber("1.00000000000000000001"))
    var context = scalar.context
    #expect(!ModelValueConstraints([.maximum(.init("1"))]).isValid(.number("1"), context: &context))
    #expect(context.diagnostics.map(\.reason) == [.maximum])
  }

  @Test func wireCaptureKeepsNestedNumericStringsNullsAndExactNumbers() throws {
    struct Input: Decodable {
      let context: ModelValidationContext
      init(from decoder: Decoder) throws {
        context = try .decoding(decoder, retainValues: true)
      }
    }
    let wire = #"{"x":{"string":"1","number":9007199254740993,"items":[null,false,"false",0.1234567890123456789]}}"#
    let input = try Foundation.JSONDecoder().decode(Input.self, from: Data(wire.utf8))
    #expect(input.context.presence(of: .property("missing"), inferred: .null) == .omitted)
    #expect(input.context.presence(of: .property("x"), inferred: .null) == .value)
    let nested = input.context.originalFields!["x"]!.fields!
    #expect(nested["string"]!.kind == .string)
    #expect(nested["number"]!.number == ModelValidationNumber("9007199254740993"))
    #expect(nested["items"]!.elements!.map(\.kind) == [.null, .boolean, .string, .number])
    #expect(nested["items"]!.elements![3].number == ModelValidationNumber("0.1234567890123456789"))
    #expect(input.context.matches { $0.originalFields?["x"]?.kind == .object })
  }

  @Test func jsonCapturePreservesNumbersBeyondDecimalAndDoublePrecision() throws {
    struct Input: Decodable {
      let context: ModelValidationContext
      init(from decoder: Decoder) throws {
        context = try .decoding(decoder, retainValues: true)
      }
    }
    let literal = "1.00000000000000000000000000000000000000000000000001e200"
    let decoder = PotentJSON.JSONDecoder()
    let number = try decoder.decode(ModelValidationNumber.self, from: Data(literal.utf8))
    #expect(number == ModelValidationNumber(literal))
    #expect(number > ModelValidationNumber("1e200"))
    #expect(!number.isMultipleOf(digits: [1], exponent: 200))
    let huge = try decoder.decode(ModelValidationNumber.self, from: Data("1e300".utf8))
    #expect(huge == ModelValidationNumber("1e300"))
    let input = try decoder.decode(Input.self, from: Data("{\"values\":[\(literal),1e300]}".utf8))
    let numbers = try #require(input.context.originalFields?["values"]?.elements)
    #expect(numbers.map(\.number) == [number, huge])
    for invalid in ["true", "null", "\"123\""] {
      #expect(throws: DecodingError.self) {
        try decoder.decode(ModelValidationNumber.self, from: Data(invalid.utf8))
      }
    }
  }

}
