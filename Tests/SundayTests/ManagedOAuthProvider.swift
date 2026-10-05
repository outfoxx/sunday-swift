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
import CryptoKit
import Darwin
import Foundation

// Package-test fixture owns provider processes and verified caches on the host.
actor ManagedOAuthProvider {
  enum Failure: Error { case configuration, integrity, startup(String), process }
  let mode: String
  let backend: String
  let realm = "sunday-" + UUID().uuidString.lowercased()
  let callback = "http://127.0.0.1:49173/callback"
  let directory: URL
  let cache: URL
  private(set) var base = ""
  private(set) var issuer = ""
  private var process: Process?
  private var container: String?
  private let session = URLSession(configuration: .ephemeral)

  init(mode: String = ProcessInfo.processInfo.environment["SUNDAY_OAUTH_TEST_MODE"] ?? "replay") throws {
    self.mode = mode
    backend = try Self.selectBackend(mode: mode, ci: ProcessInfo.processInfo.environment["CI"], macOS: true)
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("sunday-oauth-" + UUID().uuidString)
    cache = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".build/oauth-artifacts")
  }

  static func selectBackend(mode: String, ci ciValue: String?, macOS: Bool) throws -> String {
    guard ["replay", "live"].contains(mode) else { throw Failure.configuration }
    if mode == "replay" { return "wiremock-java" }
    let enabled = ciValue.map { !["", "0", "false"].contains($0.lowercased()) } ?? false
    return macOS && enabled ? "keycloak-java" : "keycloak-container"
  }

  func start() async throws {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let port = try Self.availablePort()
      base = "http://127.0.0.1:\(port)"
      issuer = "\(base)/realms/\(realm)"
      let command = try await command(port: Int(port))
      process = try launch(command, log: "provider.log")
      let readiness = mode == "replay" ? base + "/__admin/mappings" : issuer + "/.well-known/openid-configuration"
      let deadline = ContinuousClock.now.advanced(by: .seconds(120))
      while ContinuousClock.now < deadline {
        guard process?.isRunning == true else { throw Failure.process }
        var request = URLRequest(url: URL(string: readiness)!)
        request.timeoutInterval = 1
        if let (_, response) = try? await session.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200 { return }
        try await Task.sleep(for: .milliseconds(100))
      }
      throw Failure.process
    }
    catch {
      await close()
      throw Failure.startup(backend)
    }
  }

  private func command(port: Int) async throws -> [String] {
    if mode == "replay" {
      let jar = try await artifact(
        "https://repo.maven.apache.org/maven2/org/wiremock/wiremock-standalone/3.13.1/wiremock-standalone-3.13.1.jar",
        checksum: "bdf4c705e7fd61c778e59a19f75396eac4520efeabfac97643a53979bd4d5716"
      )
      return ["java", "-jar", jar.path, "--bind-address", "127.0.0.1", "--port", String(port)]
    }
    let imports = directory.appendingPathComponent("import")
    try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
    let realmFile = imports.appendingPathComponent(realm + "-realm.json")
    try JSONSerialization.data(withJSONObject: realmConfiguration()).write(to: realmFile)
    let options = ["start-dev", "--import-realm", "--http-port", String(port), "--hostname", base]
    if backend == "keycloak-java" {
      let archive = try await artifact(
        "https://github.com/keycloak/keycloak/releases/download/26.2.5/keycloak-26.2.5.tar.gz",
        checksum: "e99e5f8783ea8f1cc04140b7033ea7291ff9898a088f37399b88651d81238f88"
      )
      try await run(["tar", "-xzf", archive.path, "-C", directory.path], timeout: 60)
      let distribution = directory.appendingPathComponent("keycloak-26.2.5")
      let destination = distribution.appendingPathComponent("data/import")
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      try FileManager.default.copyItem(
        at: realmFile, to: destination.appendingPathComponent(realmFile.lastPathComponent)
      )
      return [distribution.appendingPathComponent("bin/kc.sh").path] + options + ["--http-host", "127.0.0.1"]
    }
    container = "sunday-oauth-" + UUID().uuidString.lowercased()
    return ["docker", "run", "--rm", "--name", container!, "-p", "127.0.0.1:\(port):\(port)",
            "-v", imports.path + ":/opt/keycloak/data/import:ro",
            "quay.io/keycloak/keycloak@sha256:4883630ef9db14031cde3e60700c9a9a8eaf1b5c24db1589d6a2d43de38ba2a9",
    ] + options
  }

  private func realmConfiguration() -> [String: Any] {
    let clients: [[String: Any]] = ["public", "basic", "post"].map { name in
      ["clientId": name, "enabled": true, "publicClient": name == "public", "secret": "synthetic-secret",
       "clientAuthenticatorType": "client-secret", "standardFlowEnabled": true,
       "serviceAccountsEnabled": name != "public", "redirectUris": [callback], "protocol": "openid-connect",
       "attributes": ["pkce.code.challenge.method": "S256"],
    ]
    }
    return ["realm": realm, "enabled": true, "sslRequired": "none", "revokeRefreshToken": true,
            "refreshTokenMaxReuse": 0, "clients": clients,
            "users": [["username": "synthetic-user", "enabled": true, "email": "synthetic@example.invalid",
                       "emailVerified": true, "firstName": "Synthetic", "lastName": "User",
                       "credentials": [["type": "password", "value": "synthetic-password", "temporary": false]],
    ],
    ],
    ]
  }

  private func artifact(_ raw: String, checksum: String) async throws -> URL {
    let url = URL(string: raw)!
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let target = cache.appendingPathComponent(url.lastPathComponent)
    if FileManager.default.fileExists(atPath: target.path) {
      guard try digest(target) == checksum else { throw Failure.integrity }
      return target
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 180
    let (temporary, response) = try await session.download(for: request)
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          try digest(temporary) == checksum else { throw Failure.integrity }
    try FileManager.default.moveItem(at: temporary, to: target)
    return target
  }

  private func digest(_ url: URL) throws -> String {
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    var digest = SHA256()
    while let data = try input.read(upToCount: 65536), !data.isEmpty { digest.update(data: data) }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func launch(_ arguments: [String], log: String) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    let logURL = directory.appendingPathComponent(log)
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: logURL)
    defer { try? output.close() }
    process.standardOutput = output
    process.standardError = output
    try process.run()
    return process
  }

  private func run(_ arguments: [String], timeout: Int) async throws {
    let process = try launch(arguments, log: UUID().uuidString + ".log")
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    do {
      while process.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
      guard !process.isRunning, process.terminationStatus == 0 else { throw Failure.process }
    }
    catch {
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      throw error
    }
  }

  func authorize(clientID: String) async throws -> (code: String, verifier: String) {
    if mode == "replay" { return ("synthetic-code", String(repeating: "v", count: 64)) }
    let browser = cache.appendingPathComponent("browser")
    if !FileManager.default.fileExists(atPath: browser.appendingPathComponent("node_modules/playwright").path) {
      try? FileManager.default.removeItem(at: browser)
      let bundled = Bundle.module.resourceURL!.appendingPathComponent("oauth-browser")
      try FileManager.default.copyItem(at: bundled, to: browser)
      try await run(["npm", "ci", "--prefix", browser.path, "--ignore-scripts"], timeout: 180)
      try await run(["node", browser.appendingPathComponent("node_modules/playwright/cli.js").path,
                     "install", "chromium",
    ], timeout: 240)
    }
    let configuration = directory.appendingPathComponent("browser-configuration.json")
    let result = directory.appendingPathComponent("browser-result.json")
    defer { try? FileManager.default.removeItem(at: result) }
    try JSONSerialization.data(withJSONObject: ["issuer": issuer, "callback": callback, "clientId": clientID])
      .write(to: configuration)
    try await run(
      ["node", browser.appendingPathComponent("authorize.mjs").path, configuration.path, result.path], timeout: 45
    )
    struct Grant: Decodable { let code: String; let verifier: String }
    let grant = try JSONDecoder().decode(Grant.self, from: Data(contentsOf: result))
    return (grant.code, grant.verifier)
  }

  func close() async {
    if let container {
      try? await run(["docker", "rm", "-f", container], timeout: 20)
      self.container = nil
    }
    if let process, process.isRunning {
      process.terminate()
      let deadline = ContinuousClock.now.advanced(by: .seconds(10))
      while process.isRunning, !Task.isCancelled, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(100))
      }
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    process = nil
    try? FileManager.default.removeItem(at: directory)
  }

  private static func availablePort() throws -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw Failure.process }
    defer { Darwin.close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let status = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard status == 0 else { throw Failure.process }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let result = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    guard result == 0 else { throw Failure.process }
    return UInt16(bigEndian: address.sin_port)
  }
}
#endif
