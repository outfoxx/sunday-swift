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

import Sunday
import Testing

struct PatchHashableTests {
  @Test func updateOperationsPreserveStatesAndValuesInHashedCollections() {
    let operations: Set<UpdateOp<String>> = [.unchanged, .unchanged, .set(""), .set("value"), .set("value")]
    #expect(operations.count == 3)
    #expect(operations.contains(.unchanged))
    #expect(operations.contains(.set("")))
    #expect(operations.contains(.set("value")))
    #expect(!operations.contains(.set("other")))

    var values: [UpdateOp<String>: Int] = [.unchanged: 1, .set(""): 2, .set("value"): 3]
    values[.set("value")] = 4
    #expect(values.count == 3)
    #expect(values[.unchanged] == 1)
    #expect(values[.set("")] == 2)
    #expect(values[.set("value")] == 4)
  }

  @Test func patchOperationsPreserveStatesAndValuesInHashedCollections() {
    let operations: Set<PatchOp<String>> = [
      .unchanged, .unchanged, .delete, .delete, .set(""), .set("value"), .set("value"),
    ]
    #expect(operations.count == 4)
    #expect(operations.contains(.unchanged))
    #expect(operations.contains(.delete))
    #expect(operations.contains(.set("")))
    #expect(operations.contains(.set("value")))
    #expect(!operations.contains(.set("other")))

    var values: [PatchOp<String>: Int] = [.unchanged: 1, .delete: 2, .set(""): 3, .set("value"): 4]
    values[.set("value")] = 5
    #expect(values.count == 4)
    #expect(values[.unchanged] == 1)
    #expect(values[.delete] == 2)
    #expect(values[.set("")] == 3)
    #expect(values[.set("value")] == 5)
  }

  @Test func hashabilityPropagatesThroughNestedModelsAndCollections() {
    let unchanged = Fields()
    let cleared = Fields(note: .delete)
    let empty = Fields(note: .set(""))
    #expect(Set([unchanged, Fields(), cleared, empty]).count == 3)
    #expect(Set<UpdateOp<Fields>>([.unchanged, .set(unchanged), .set(Fields()), .set(cleared)]).count == 3)
    #expect(Set<PatchOp<[Fields]>>([
      .unchanged, .delete, .set([]), .set([cleared]), .set([Fields(note: .delete)]),
    ]).count == 4)
  }

  @Test func generatedStyleIdentifiableModelsCanExposeOperationIDs() {
    let updates = [UpdateIdentity(), UpdateIdentity(ownerID: .set("owner"))]
    #expect(Set(updates.map(\.id)) == Set<UpdateOp<String>>([.unchanged, .set("owner")]))
    let patches = [PatchIdentity(), PatchIdentity(ownerID: .delete), PatchIdentity(ownerID: .set("owner"))]
    #expect(Set(patches.map(\.id)) == Set<PatchOp<String>>([.unchanged, .delete, .set("owner")]))
  }

  @Test func nonHashableValuesRemainSupported() {
    let value = EquatableValue(value: "value")
    #expect(UpdateOp.set(value) == UpdateOp.set(EquatableValue(value: "value")))
    #expect(PatchOp.set(value) == PatchOp.set(EquatableValue(value: "value")))
    #expect(UpdateOp<EquatableValue>.unchanged != .set(value))
    #expect(PatchOp<EquatableValue>.delete != .set(value))
  }

  private struct Fields: Codable, Hashable, Sendable {
    var name: UpdateOp<String> = .unchanged
    var note: PatchOp<String> = .unchanged
  }

  // Generated PATCH models expose their identity property through the operation wrapper.
  private struct UpdateIdentity: Identifiable {
    var ownerID: UpdateOp<String> = .unchanged
    var id: UpdateOp<String> { ownerID }
  }

  private struct PatchIdentity: Identifiable {
    var ownerID: PatchOp<String> = .unchanged
    var id: PatchOp<String> { ownerID }
  }

  private struct EquatableValue: Codable, Equatable, Sendable {
    var value: String
  }
}
