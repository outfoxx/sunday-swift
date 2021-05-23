/*
 * Copyright 2021 Outfox, Inc.
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


public class TrackInvocations: Routable {

  let name: String
  let routable: Routable
  var count: Int = 0

  public init(name: String, @RoutableBuilder routableBuilder: () -> Routable) {
    self.name = name
    routable = routableBuilder()
  }

  public func route(_ route: SundayServer.Route, request: HTTPRequest) throws -> RouteResult? {
    guard let routed = try routable.route(route, request: request) else {
      return nil
    }
    let handler: RouteHandler = { route, request, response in
      defer { self.count += 1 }
      response.properties[self.name] = self.count
      try routed.handler(route, request, response)
    }
    return (routed.route, handler)
  }

}
