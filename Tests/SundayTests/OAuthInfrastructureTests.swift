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

#if os(macOS)
import Foundation
@testable import SundayServer
import Testing

struct OAuthInfrastructureTests {
  @Test(arguments: [[], ["/usr/bin/false"], ["/bin/sleep", "60"]])
  func startupFailuresCleanDirectory(command: [String]) async throws {
    let provider = try ManagedOAuthProvider(startupTimeout: .milliseconds(100), command: command)
    do {
      try await provider.start()
      Issue.record("An unready provider must fail")
    }
    catch ManagedOAuthProvider.Failure.startup(let backend) {
      #expect(backend == "wiremock-java")
    }
    #expect(!FileManager.default.fileExists(atPath: provider.directory.path))
    await provider.close()
  }

  @Test func macCICacheFailureUsesJavaAndCleansDirectory() async throws {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cache) }
    try Data("tampered".utf8).write(to: cache.appendingPathComponent("keycloak-26.2.5.tar.gz"))
    let provider = try ManagedOAuthProvider(mode: "live", ci: "true", cache: cache)
    do {
      try await provider.start()
      Issue.record("A corrupt artifact must fail before launching any process")
    }
    catch ManagedOAuthProvider.Failure.startup(let backend) {
      #expect(backend == "keycloak-java")
    }
    #expect(!FileManager.default.fileExists(atPath: provider.directory.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path) == ["keycloak-26.2.5.tar.gz"])
    await provider.close()
  }
  @Test func rejectedDownloadDoesNotPopulateCache() async throws {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = try RoutingHTTPServer(port: .any, localOnly: true) {
      Path("/provider.jar") { GET { _, res in res.send(status: .ok, text: "tampered") } }
    }
    let base = try await startTestServer(server)
    defer { server.stop() }
    let provider = try ManagedOAuthProvider(cache: cache)
    await #expect(throws: ManagedOAuthProvider.Failure.self) {
      try await provider.artifact(base.appendingPathComponent("provider.jar").absoluteString, checksum: "invalid")
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
    await provider.close()
  }

}
#endif
