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
@testable import Sunday
import Synchronization
import Testing

struct RequestValidationTests {

  final class Body: Encodable, ModelValidatable, Sendable {
    struct State: Sendable {
      var unknown = false
      var validations = 0
      var encodings = 0
    }
    let state = Mutex(State())

    func isValid(_ mode: ModelMode, context: inout ModelValidationContext) -> Bool {
      state.withLock { state in
        state.validations += 1
        return mode != .request || !state.unknown || context.reject(.unknownEnum)
      }
    }

    func encode(to encoder: any Encoder) throws {
      let value = state.withLock { state in
        state.encodings += 1
        return state.unknown ? "future" : "active"
      }
      var container = encoder.singleValueContainer()
      try container.encode(value)
    }
  }

  @Test func deferredOperationsValidateAgainImmediatelyBeforeEveryEncoding() async throws {
    let body = Body()
    let transport = URLSessionTransport(baseURL: URI.Template(format: "https://example.com"))
    defer { transport.close() }
    let operation = Operation<Body, Void, URLSessionTransport>(
      transport: transport,
      spec: OperationSpec(method: .put, pathTemplate: "/items/123", body: body, contentTypes: [.json],
                          requestValidation: { try $0.validate(.request) })
    )
    #expect(body.state.withLock { $0.validations } == 0)
    let first = try await operation.transportRequest()
    #expect(first.httpBody == Data(#""active""#.utf8))
    #expect(body.state.withLock { $0.validations } == 1)
    #expect(body.state.withLock { $0.encodings } == 1)
    body.state.withLock { $0.unknown = true }
    do {
      _ = try await operation.transportRequest()
      Issue.record("Expected request validation to reject mutation")
    }
    catch let SundayError.requestEncodingFailed(reason) {
      guard case .serializationFailed(_, let error) = reason else {
        Issue.record("Expected a validation error at encoding")
        return
      }
      #expect(error is ModelValidationError)
    }
    #expect(body.state.withLock { $0.validations } == 2)
    #expect(body.state.withLock { $0.encodings } == 1)
    body.state.withLock { $0.unknown = false }
    _ = try await operation.transportRequest()
    #expect(body.state.withLock { $0.validations } == 3)
    #expect(body.state.withLock { $0.encodings } == 2)
  }
  @Test func eventConveniencesValidateMutationsBeforeEncoding() async throws {
    let body = Body()
    let transport = URLSessionTransport(baseURL: URI.Template(format: "https://example.com"))
    defer { transport.close() }
    let source = transport.eventSource(
      method: .post, pathTemplate: "/events", body: body, contentTypes: [.json],
      requestValidation: { try $0.validate(.request) }
    )
    body.state.withLock { $0.unknown = true }
    let (closed, continuation) = AsyncStream<Void>.makeStream()
    await source.setOnStateError { error, state in
      if error != nil, state == .closed { continuation.yield(()); continuation.finish() }
    }
    await source.connect()
    for await _ in closed { break }
    await source.close()
    #expect(body.state.withLock { $0.validations } == 1)
    #expect(body.state.withLock { $0.encodings } == 0)
    let stream: AsyncStream<String> = transport.eventStream(
      method: .post, pathTemplate: "/events", body: body, contentTypes: [.json],
      requestValidation: { try $0.validate(.request) },
      decoder: { _, _, _, data, _ in data }
    )
    for await _ in stream { Issue.record("Invalid body must not produce events") }
    #expect(body.state.withLock { $0.validations } == 2)
    #expect(body.state.withLock { $0.encodings } == 0)
  }

  @Test func bodylessRequestsValidateParametersOnEveryBuild() async throws {
    let parameter = Body()
    let transport = URLSessionTransport(baseURL: URI.Template(format: "https://example.com"))
    defer { transport.close() }
    let operation = Operation<Empty, Void, URLSessionTransport>(
      transport: transport,
      spec: OperationSpec(method: .get, pathTemplate: "/parameters",
                          queryParameters: ["state": "known"],
                          parameterValidation: { try parameter.validate(.request) })
    )
    #expect(parameter.state.withLock { $0.validations } == 0)
    let request = try await operation.transportRequest()
    #expect(request.httpBody == nil)
    #expect(parameter.state.withLock { $0.validations } == 1)
    parameter.state.withLock { $0.unknown = true }
    do {
      _ = try await operation.transportRequest()
      Issue.record("Expected parameter validation failure")
    }
    catch is ModelValidationError {
      #expect(parameter.state.withLock { $0.validations } == 2)
    }
  }

}
