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

/// Resolves a complete credential alternative without changing payload encoding or application models.
struct RequestSecurity: Sendable {
  let bindings: [SecurityBinding]
  let providers: [String: any TokenProvider]

  func authorize(_ request: URLRequest) async throws -> (URLRequest, [TokenLease]) {
    var targets = Set<String>()
    for binding in bindings {
      let transport = binding.transport
      let name = transport.location == .header ? transport.name.lowercased() : transport.name
      guard targets.insert(transport.location.rawValue + ":" + name).inserted else { throw TokenProviderError() }
      let conflict: Bool
      switch transport.location {
      case .header: conflict = request.value(forHTTPHeaderField: name) != nil
      case .query: conflict = queryEntries(request.url).contains { $0.name == name }
      case .cookie: conflict = cookies(request).contains { $0.0 == name }
      }
      guard !conflict else { throw TokenProviderError() }
    }
    var leases: [TokenLease] = []
    for binding in bindings {
      guard let provider = providers[binding.provider] else { throw TokenProviderError() }
      try leases.append(await provider.credentials(for: binding))
    }
    var result = request
    result.httpShouldHandleCookies = false
    for (binding, lease) in zip(bindings, leases) {
      let transport = binding.transport
      let credential = transport.prefix.map { $0 + " " + lease.tokens.accessToken } ?? lease.tokens.accessToken
      switch transport.location {
      case .header:
        guard !credential.utf8.contains(where: { $0 < 32 || $0 == 127 }) else { throw TokenProviderError() }
        result.setValue(credential, forHTTPHeaderField: transport.name)
      case .query: result.url = try settingQuery(result.url, name: transport.name, value: credential)
      case .cookie:
        let values = cookies(result).filter { $0.0 != transport.name } + [(transport.name, encode(credential))]
        result.setValue(values.map { $0.0 + "=" + $0.1 }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
      }
    }
    return (result, leases)
  }

  func reject(_ response: HTTPURLResponse, for request: URLRequest, leases: [TokenLease]) async throws {
    guard response.statusCode == 401,
          BearerChallenge.isInvalidToken(response.value(forHTTPHeaderField: "WWW-Authenticate") ?? "") else { return }
    let rejected = zip(bindings, leases).filter { binding, lease in
      binding.transport.location == .header && binding.transport.name.lowercased() == "authorization" &&
        binding.transport.prefix?.lowercased() == "bearer" &&
        BearerChallenge.token(in: request.value(forHTTPHeaderField: binding.transport.name)) == lease.tokens.accessToken
    }.map(\.1)
    var recoverable = true
    for lease in rejected {
      let recovered = try await lease.invalidate()
      recoverable = recovered && recoverable
    }
    if !recoverable { throw TokenRejectedError(response: try redact(response)) }
  }

  func redact(_ response: HTTPURLResponse) throws -> HTTPURLResponse {
    var url = response.url
    for binding in bindings where binding.transport.location == .query {
      url = try settingQuery(url, name: binding.transport.name, value: "[redacted]")
    }
    return try response.clone(url: url)
  }

  private func cookies(_ request: URLRequest) -> [(String, String)] {
    (request.value(forHTTPHeaderField: "Cookie") ?? "").split(separator: ";").compactMap {
      let parts = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { return nil }
      return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
    }
  }

  private func queryEntries(_ url: URL?) -> [(name: String, raw: String)] {
    guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
    return (parts.percentEncodedQuery ?? "").split(separator: "&").map { entry in
      let name = String(entry.split(separator: "=", maxSplits: 1).first ?? "")
        .replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
      return (name, String(entry))
    }
  }

  private func settingQuery(_ url: URL?, name: String, value: String) throws -> URL {
    guard let url,
          var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw TokenProviderError() }
    parts.percentEncodedQuery = (
      queryEntries(url).filter { $0.name != name }.map(\.raw) +
        [encode(name) + "=" + encode(value)]
    ).joined(separator: "&")
    guard let result = parts.url else { throw TokenProviderError() }
    return result
  }

  private func encode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: CharacterSet(
      charactersIn:
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )) ?? ""
  }

}
