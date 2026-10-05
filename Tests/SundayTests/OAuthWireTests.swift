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
import Testing

struct OAuthWireTests {
  struct Corpus: Decodable {
    let formatVersion: Int
    let cases: [Case]
  }
  struct Case: Decodable {
    let id: String
    let kind: String
    let body: String
    let expected: String
    let context: Context
  }
  struct Context: Decodable {
    let scopes: Set<String>
    let clockMillis: Double
  }

  @Test func specificationFixtures() throws {
    let url = try #require(Bundle.module.url(forResource: "oauth-cases", withExtension: "json"))
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    #expect(corpus.formatVersion == 1)
    for fixture in corpus.cases {
      let accepted = Result {
        let data = Data(fixture.body.utf8)
        switch fixture.kind {
        case "discovery": _ = try JSONDecoder().decode(OAuthWire.Discovery.self, from: data)
        case "error": _ = try JSONDecoder().decode(OAuthWire.Failure.self, from: data)
        default:
          _ = try JSONDecoder().decode(OAuthWire.Success.self, from: data)
            .tokens(
              scopes: fixture.context.scopes, now: Date(timeIntervalSince1970: fixture.context.clockMillis / 1000)
            )
        }
      }
      switch accepted {
      case .success: #expect(fixture.expected == "accept", "\(fixture.id)")
      case .failure: #expect(fixture.expected != "accept", "\(fixture.id)")
      }
    }
  }
}
