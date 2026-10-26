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

struct PatchProtocolPayloadTests {
  @Test func protocolValuesAreStoredWithoutCodingWrappers() throws {
    let value: any Named = Name(value: "Misty")
    let patch: PatchOp<[any Named]> = .set([value])
    let update: UpdateOp<any Named> = .merge(value)
    #expect(patch.get(deleted: [])?[0].value == "Misty")
    #expect(update.get()?.value == "Misty")

    let wire = patch.map { $0.map { Name(value: $0.value) } }
    let decoded = try JSONDecoder().decode(PatchOp<[Name]>.self, from: JSONEncoder().encode(wire))
    let stored: PatchOp<[any Named]> = decoded.map { $0.map { $0 as any Named } }
    #expect(stored.get(deleted: [])?.first is Name)
  }

  @Test func mappingPreservesStatesAndOnlyTransformsSuppliedValues() throws {
    var calls = 0
    let transform: (String) throws -> Int = { _ in
      calls += 1
      throw Failure.expected
    }
    #expect(try UpdateOp<String>.unchanged.map(transform) == .unchanged)
    #expect(try PatchOp<String>.unchanged.map(transform) == .unchanged)
    #expect(try PatchOp<String>.delete.map(transform) == .delete)
    #expect(calls == 0)
    #expect(throws: Failure.expected) { try UpdateOp.set("value").map(transform) }
    #expect(throws: Failure.expected) { try PatchOp.set("value").map(transform) }
    #expect(calls == 2)
    #expect(UpdateOp.set("value").map(\.count) == .set(5))
    #expect(PatchOp.set("value").map(\.count) == .set(5))
  }

  @Test func codingConformancesAreIndependent() throws {
    let input = Data(#"{"update":{"value":"name"},"patch":null}"#.utf8)
    let decoded = try JSONDecoder().decode(DecodeOnlyFields.self, from: input)
    #expect(decoded.update.get()?.value == "name")
    guard case .delete = decoded.patch else { Issue.record("Expected deletion"); return }
    let omitted = try JSONDecoder().decode(DecodeOnlyFields.self, from: Data("{}".utf8))
    #expect(omitted.update.isUnchanged)
    #expect(omitted.patch.isUnchanged)

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let fields = EncodeOnlyFields(update: .set(.init(value: "name")), patch: .delete)
    #expect(String(data: try encoder.encode(fields), encoding: .utf8) ==
      #"{"patch":null,"update":{"value":"name"}}"#)
    #expect(String(data: try encoder.encode(EncodeOnlyFields()), encoding: .utf8) == "{}")
  }

  private protocol Named: Sendable {
    var value: String { get }
  }

  private struct Name: Named, Codable {
    let value: String
  }

  private struct DecodeOnly: Decodable, Sendable {
    let value: String
  }

  private struct EncodeOnly: Encodable, Sendable {
    let value: String
  }

  private struct DecodeOnlyFields: Decodable {
    var update: UpdateOp<DecodeOnly>
    var patch: PatchOp<DecodeOnly>
  }

  private struct EncodeOnlyFields: Encodable {
    var update: UpdateOp<EncodeOnly> = .unchanged
    var patch: PatchOp<EncodeOnly> = .unchanged
  }

  private enum Failure: Error {
    case expected
  }
}
