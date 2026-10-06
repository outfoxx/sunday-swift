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

/// Immutable endpoint and security settings supplied to an application's transport factory.
public struct ClientSettings: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public let baseURL: URL
  public let bindings: [String: [SecurityBinding]]
  /// Prepared manager shared by this configuration's operations, without acquiring tokens.
  public let tokenManager: TokenManager?

  /// Validates endpoint and credential compatibility without performing network I/O.
  public init(
    baseURL: URL,
    bindings: [String: [SecurityBinding]] = [:],
    credentials: [String: any Credentials] = [:]
  ) throws {
    guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""), baseURL.host != nil,
          baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else {
      throw TokenProviderError()
    }
    self.baseURL = baseURL
    self.bindings = try bindings.mapValues { values in
      try values.map { binding in
        func endpoint(_ value: String?) throws -> String? {
          guard let value else { return nil }
          guard !value.contains("{"), !value.contains("}"), let url = URL(string: value, relativeTo: baseURL) else {
            throw TokenProviderError()
          }
          return url.absoluteURL.absoluteString
        }
        return try binding.overridingEndpoints(.init(
          discoveryURL: endpoint(binding.endpoints.discoveryURL),
          authorizationURL: endpoint(binding.endpoints.authorizationURL),
          tokenURL: endpoint(binding.endpoints.tokenURL), refreshURL: endpoint(binding.endpoints.refreshURL)
        ))
      }
    }
    for binding in bindings.values.flatMap({ $0 }) {
      guard let credential = credentials[binding.scheme] else { throw TokenProviderError() }
      try Self.validate(credential, binding: binding)
    }
    tokenManager = try Self.prepareTokenManager(baseURL: baseURL, bindings: self.bindings, credentials: credentials)
  }

  private static func prepareTokenManager(
    baseURL: URL,
    bindings: [String: [SecurityBinding]],
    credentials: [String: any Credentials]
  ) throws -> TokenManager? {
    var owners: [String: String] = [:]
    var providers: [String: any TokenProvider] = [:]
    for binding in bindings.values.flatMap({ $0 }) {
      if let owner = owners[binding.provider] {
        guard owner == binding.scheme else { throw TokenProviderError() }
        continue
      }
      owners[binding.provider] = binding.scheme
      guard let credential = credentials[binding.scheme] else { throw TokenProviderError() }
      switch credential {
      case let value as ProviderCredentials: providers[binding.provider] = value.provider
      case let value as OAuthCredentials: providers[binding.provider] = try value.makeProvider(baseURL: baseURL)
      case let value as BearerCredentials: providers[binding.provider] = StaticProvider(token: value.token)
      case let value as ApiKeyCredentials: providers[binding.provider] = StaticProvider(token: value.key)
      case let value as BasicCredentials:
        providers[binding.provider] = StaticProvider(
          token: Data("\(value.username):\(value.password)".utf8)
            .base64EncodedString()
        )
      default: throw TokenProviderError()
      }
    }
    return providers.isEmpty ? nil : try TokenManager(providers: providers)
  }

  /// Expands variables once and resolves relative servers against their document location.
  public static func serverURL(
    template: String,
    variables: [String: String],
    documentBaseURL: URL? = nil
  ) throws -> URL {
    let regex = try NSRegularExpression(pattern: "\\{([^}]+)\\}")
    var expanded = template
    for match in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
      guard let nameRange = Range(match.range(at: 1), in: template), let range = Range(match.range, in: expanded),
            let value = variables[String(template[nameRange])] else { throw TokenProviderError() }
      expanded.replaceSubrange(range, with: value)
    }
    guard let url = URL(string: expanded, relativeTo: documentBaseURL)?.absoluteURL,
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
          url.user == nil, url.password == nil, url.query == nil,
          url.fragment == nil else { throw TokenProviderError() }
    return url
  }

  /// Selects complete operation alternatives without acquiring credentials or constructing a transport.
  /// `alternativeSelection` chooses a zero-based candidate index, including scopes and endpoint metadata.
  public static func resolve(
    baseURL: URL, alternatives: [String: [[SecurityBinding]]], credentials: [String: any Credentials],
    selection: [String: Set<String>] = [:], alternativeSelection: [String: Int] = [:]
  ) throws -> ClientSettings {
    guard Set(selection.keys).union(alternativeSelection.keys).allSatisfy({ alternatives[$0] != nil }) else {
      throw TokenProviderError()
    }
    var bindings: [String: [SecurityBinding]] = [:]
    for (operation, candidates) in alternatives {
      let usable = candidates.enumerated().filter { index, candidate in
        if let selected = alternativeSelection[operation], selected != index { return false }
        if let selected = selection[operation], selected != Set(candidate.map(\.scheme)) { return false }
        return candidate.allSatisfy { binding in
          guard let credential = credentials[binding.scheme] else { return false }
          do {
            try validate(credential, binding: binding)
            return true
          }
          catch {
            return false
          }
        }
      }
      guard usable.count == 1 else { throw TokenProviderError() }
      bindings[operation] = usable[0].element
    }
    return try ClientSettings(baseURL: baseURL, bindings: bindings, credentials: credentials)
  }

  public var description: String { "ClientSettings()" }
  public var debugDescription: String { description }

  private static func validate(_ credential: any Credentials, binding: SecurityBinding) throws {
    let prefix = binding.transport.prefix?.lowercased()
    if let value = credential as? ProviderCredentials {
      guard value.flow == nil || value.flow == binding.flow else { throw TokenProviderError() }
      return
    }
    if let value = credential as? OAuthCredentials {
      let config = value.configuration
      guard prefix == "bearer", value.flow == binding.flow,
            !config.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !config.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            (config.authentication == .none) == (config.clientSecret == nil), config.clientSecret != ""
      else { throw TokenProviderError() }
      switch value {
      case .clientCredentials:
        guard config.authentication != .none else { throw TokenProviderError() }
      case .authorizationCode:
        guard let grant = config.grantIdentity, !grant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              config.authorize != nil else { throw TokenProviderError() }
      }
      return
    }
    guard binding.flow == .static || binding.flow == .external else { throw TokenProviderError() }
    switch credential {
    case let value as BearerCredentials:
      guard prefix == "bearer", !value.token.isEmpty else { throw TokenProviderError() }
    case let value as ApiKeyCredentials:
      guard prefix == nil, !value.key.isEmpty else { throw TokenProviderError() }
    case let value as BasicCredentials:
      guard prefix == "basic", !value.username.contains(":") else { throw TokenProviderError() }
    default: throw TokenProviderError()
    }
  }

  private struct StaticProvider: TokenProvider {
    let identity = UUID().uuidString
    let token: String
    func configure(_: SecurityBinding) -> TokenConfiguration { .init(clientIdentity: identity) }
    func acquire(_: TokenRequest) async throws -> TokenSet { .init(accessToken: token) }
  }
}
