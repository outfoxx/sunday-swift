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

// Wire decoding preserves absence separately from explicit null before applying client policy.
internal enum OAuthWire {
  struct Discovery: Decodable {
    let issuer: String
    let tokenEndpoint: String?
    let authorizationEndpoint: String?
    let authenticationMethods: [String]?

    init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: Key.self)
      issuer = try values.string("issuer")
      tokenEndpoint = try values.optionalString("token_endpoint")
      authorizationEndpoint = try values.optionalString("authorization_endpoint")
      for name in [
        "token_endpoint", "authorization_endpoint", "jwks_uri",
        "registration_endpoint", "revocation_endpoint", "introspection_endpoint",
      ] {
        if let value = try values.optionalString(name) { _ = try endpoint(value) }
      }
      let methods = Key("token_endpoint_auth_methods_supported")
      authenticationMethods = values.contains(methods) ? try values.decode([String].self, forKey: methods) : nil
    }
  }

  struct Success: Decodable, CustomStringConvertible {
    let accessToken: String
    let tokenType: String
    let expiresIn: Double?
    let refreshToken: String?
    let scope: String?
    var description: String { "OAuthTokenResponse()" }

    static func parse(_ data: Data) throws -> Self {
      // Foundation rejects trailing JSON that PotentJSON 3.5 accepts. Retain its strict document check.
      let result = try Foundation.JSONDecoder().decode(Self.self, from: data)
      let tree = try PotentJSON.JSONSerialization.json(from: data)
      if case .object(let fields) = tree, let lifetime = fields["expires_in"] {
        guard case .number(let number) = lifetime, integral(number.value) else { throw TokenProviderError() }
      }
      return result
    }

    // Check the original JSON number before conversion; Decimal also rounds beyond its precision.
    private static func integral(_ raw: String) -> Bool {
      let parts = raw.lowercased().split(separator: "e")
      guard let exponent = parts.count == 2 ? Int(parts[1]) : 0,
            (-10_000 ... 10_000).contains(exponent) else { return false }
      let coefficient = parts[0].split(separator: ".")
      let scale = (coefficient.count == 2 ? coefficient[1].count : 0) - exponent
      let digits = coefficient.joined()
      return scale <= 0 || digits.reversed().prefix(while: { $0 == "0" }).count >= scale
    }

    init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: Key.self)
      accessToken = try values.string("access_token")
      tokenType = try values.string("token_type")
      refreshToken = try values.optionalString("refresh_token")
      scope = try values.optionalString("scope")
      let key = Key("expires_in")
      expiresIn = values.contains(key) ? try values.decode(Double.self, forKey: key) : nil
      if let seconds = expiresIn {
        guard seconds.isFinite, seconds > 0, seconds.rounded(.towardZero) == seconds else { throw TokenProviderError() }
      }
      if let scope {
        let parts = scope.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ part in
          !part.isEmpty && part.utf8.allSatisfy {
            $0 == 0x21 || (0x23 ... 0x5B).contains($0) || (0x5D ... 0x7E).contains($0)
          }
        }) else { throw TokenProviderError() }
      }
    }

    func tokens(scopes: Set<String>, now: Date) throws -> TokenSet {
      guard tokenType.lowercased() == "bearer" else { throw TokenProviderError() }
      if let scope, !scopes.isSubset(of: Set(scope.split(separator: " ").map(String.init))) {
        throw TokenProviderError()
      }
      var expiry: Date?
      if let expiresIn {
        let millis = floor(now.timeIntervalSince1970 * 1000) + expiresIn * 1000
        guard millis.isFinite, abs(millis) <= 9_007_199_254_740_991 else { throw TokenProviderError() }
        expiry = Date(timeIntervalSince1970: millis / 1000)
      }
      return TokenSet(accessToken: accessToken, expiresAt: expiry, refreshToken: refreshToken)
    }
  }

  struct Failure: Decodable {
    let code: String
    init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: Key.self)
      code = try values.string("error")
      // Compatibility: empty advisory descriptions must not hide an invalid grant.
      if values.contains(Key("error_description")) {
        _ = try values.decode(String.self, forKey: Key("error_description"))
      }
      _ = try values.optionalString("error_uri")
    }
  }

  static func endpoint(_ raw: String) throws -> URL {
    guard let parts = URLComponents(string: raw), let host = parts.host, !host.isEmpty,
          parts.user == nil, parts.password == nil, parts.fragment == nil,
          parts.scheme == "https" ||
          (parts.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)),
          let url = parts.url else { throw TokenProviderError() }
    return url
  }

  struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue _: Int) { return nil }
  }
}

private extension KeyedDecodingContainer where Key == OAuthWire.Key {
  func string(_ name: String) throws -> String {
    let value = try decode(String.self, forKey: Key(name))
    guard !value.isEmpty else { throw TokenProviderError() }
    return value
  }

  func optionalString(_ name: String) throws -> String? {
    contains(Key(name)) ? try string(name) : nil
  }
}
