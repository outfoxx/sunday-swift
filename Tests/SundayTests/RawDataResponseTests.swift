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
import Testing

struct RawDataResponseTests {

  @Test(arguments: [
    "application/octet-stream", "application/pdf", "image/png", "audio/wav", "video/mp4",
    "application/x-turnpost-future", "application/json; charset=utf-8", "application/vnd.asset+json",
    "text/plain; charset=utf-8", "application/cbor", "image/svg+xml", "application/vnd.asset+zip",
    "application/x.asset+cbor",
  ])
  func preservesBinaryBytes(contentType: String) async throws {
    let body = Data((0 ..< 65536).map { UInt8(truncatingIfNeeded: $0) })
    try await assertDownload(body: body, contentType: contentType)
  }

  @Test(arguments: ["application/json", "text/plain; charset=utf-8"])
  func preservesTextBytes(contentType: String) async throws {
    try await assertDownload(body: Data(" { \"value\" : [1, 2, 3] }\n".utf8), contentType: contentType)
  }

  @Test(arguments: [nil, "not-a-media-type"] as [String?])
  func rawDataDoesNotRequireContentType(contentType: String?) throws {
    let transport = URLSessionTransport(
      baseURL: "https://example.com", mediaTypeDecoders: MediaTypeDecoders.Builder().build()
    )
    defer { transport.close() }
    let body = Data([0, 255, 128])
    let response = try makeResponse(contentType: contentType)
    let result: Data = try transport.parse(dataResponse: (body, response))
    #expect(result == body)
    #expect(throws: SundayError.self) {
      let _: [String] = try transport.parse(dataResponse: (body, response))
    }
  }

  @Test(arguments: [nil, Data()] as [Data?])
  func emptyBodyStillFails(body: Data?) throws {
    let transport = URLSessionTransport(baseURL: "https://example.com")
    defer { transport.close() }
    let response = try makeResponse(contentType: "application/octet-stream")
    #expect {
      let _: Data = try transport.parse(dataResponse: (body, response))
    } throws: { error in
      guard case SundayError.responseDecodingFailed(reason: .noData) = error else { return false }
      return true
    }
  }

  @Test(arguments: [204, 205])
  func bodylessStatusesStillRequireEmpty(statusCode: Int) throws {
    let transport = URLSessionTransport(baseURL: "https://example.com")
    defer { transport.close() }
    let response = try makeResponse(statusCode: statusCode)
    #expect {
      let _: Data = try transport.parse(dataResponse: (nil, response))
    } throws: { error in
      guard case SundayError.unexpectedEmptyResponse = error else { return false }
      return true
    }
    let _: Empty = try transport.parse(dataResponse: (nil, response))
  }

  @Test func nestedDataStillUsesJSONDecoding() throws {
    struct Model: Decodable {
      let value: Data
    }
    let transport = URLSessionTransport(baseURL: "https://example.com")
    defer { transport.close() }
    let response = try makeResponse(contentType: "application/json")
    let body = Data(#"{"value":"AP+A"}"#.utf8)
    let result: Model = try transport.parse(dataResponse: (body, response))
    #expect(result.value == Data([0, 255, 128]))
  }

  @Test func problemResponseStillThrowsForDataOperations() async throws {
    let body = Data(#"{"type":"about:blank","title":"Forbidden","status":403}"#.utf8)
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/asset") {
        GET { _, response in
          response.send(status: .forbidden, headers: ["Content-Type": ["application/problem+json"]], body: body)
        }
      }
    }
    let url = try await startTestServer(server)
    defer { server.stop() }
    let transport = URLSessionTransport(baseURL: URI.Template(format: url.absoluteString))
    defer { transport.close() }
    let operation = Sunday.Operation<Empty, Data, URLSessionTransport>(
      transport: transport,
      spec: OperationSpec(method: .get, pathTemplate: "/asset", body: Empty.none, acceptTypes: [.any])
    )
    await #expect { try await operation.execute() } throws: { error in
      (error as? Problem)?.status == 403
    }
    await #expect { try await operation.response() } throws: { error in
      (error as? Problem)?.status == 403
    }
  }

  private func assertDownload(body: Data, contentType: String) async throws {
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/asset") {
        GET { _, response in
          response.send(status: .ok, headers: ["Content-Type": [contentType], "X-Asset": ["original"]], body: body)
        }
      }
    }
    let url = try await startTestServer(server)
    defer { server.stop() }
    let transport = URLSessionTransport(baseURL: URI.Template(format: url.absoluteString))
    defer { transport.close() }
    let operation = Sunday.Operation<Empty, Data, URLSessionTransport>(
      transport: transport,
      spec: OperationSpec(method: .get, pathTemplate: "/asset", body: Empty.none, acceptTypes: [.any])
    )
    #expect(try await operation.execute() == body)
    let response = try await operation.response()
    #expect(response.result == body)
    #expect(response.statusCode == 200)
    #expect(response.header(named: "Content-Type") == contentType)
    #expect(response.header(named: "X-Asset") == "original")
  }

  private func makeResponse(statusCode: Int = 200, contentType: String? = nil) throws -> HTTPURLResponse {
    let url = try #require(URL(string: "https://example.com/asset"))
    return try #require(HTTPURLResponse(
      url: url, statusCode: statusCode, httpVersion: "HTTP/1.1",
      headerFields: contentType.map { ["Content-Type": $0] }
    ))
  }
}
