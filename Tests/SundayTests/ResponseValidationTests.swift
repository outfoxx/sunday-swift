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
import SundayServer
import Synchronization
import Testing

struct ResponseValidationTests {

  @Test func validatesEveryDecodedCollectionBeforeReturningIt() async throws {
    let values = Mutex([1, 2])
    let calls = Mutex(0)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      ContentNegotiation {
        Path("/values") {
          GET { _, response in
            response.send(status: .ok, value: values.withLock { $0 })
          }
        }
      }
    }
    let url = try #require(server.startLocal(timeout: 5))
    defer { server.stop() }
    let transport = URLSessionTransport(baseURL: URI.Template(format: url.absoluteString))
    defer { transport.close() }
    let validate: @Sendable ([Int]) throws -> Void = { value in
      calls.withLock { $0 += 1 }
      var context = ModelValidationContext(collectsDiagnostics: true)
      for (index, item) in value.enumerated() where item < 1 {
        _ = context.at(.index(index)) { $0.reject(.minimum) }
      }
      if !context.diagnostics.isEmpty { throw context.validationError }
    }
    let spec = OperationSpec(method: .get, pathTemplate: "/values", body: Empty.none, acceptTypes: [.json])
    let operation = Sunday.Operation<Empty, [Int], URLSessionTransport>(
      transport: transport, spec: spec, responseValidation: validate
    )
    #expect(try await operation.execute() == [1, 2])
    #expect(try await operation.response().result == [1, 2])
    #expect(calls.withLock { $0 } == 2)
    values.withLock { $0 = [1, 0] }
    await #expect(throws: ModelValidationError.self) { try await operation.execute() }
    await #expect(throws: ModelValidationError.self) { try await operation.response() }
    let nilable = NilableOperation<Empty, [Int], URLSessionTransport>(
      transport: transport, spec: spec, nilify: NilifySpec(), responseValidation: validate
    )
    await #expect(throws: ModelValidationError.self) { try await nilable.executeOrNil() }
    #expect(calls.withLock { $0 } == 5)
  }
}
