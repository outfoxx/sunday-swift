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
import Network


open class RoutingHTTPServer: NetworkHTTPServer {

  private var routableStorage: Routable!

  open var routable: Routable {
    return routableStorage
  }

  public init(
    port: NWEndpoint.Port = .any,
    localOnly: Bool = true,
    serviceName: String? = nil,
    serviceType: String? = nil
  ) throws {
    try super.init(
      port: port,
      localOnly: localOnly,
      serviceName: serviceName,
      serviceType: serviceType
    ) { request, response in
      // swiftlint:disable:next force_cast
      let routingServer = request.server as! RoutingHTTPServer
      do {
        let route = Route(matched: "", unmatched: request.url.path, parameters: [:])
        guard let routed = try routingServer.routable.route(route, request: request) else {
          return response.send(status: .notFound, text: "No method handler found")
        }

        try routed.handler(routed.route, request, response)

      }
      catch {
        response.send(status: .internalServerError, text: "\(error)")
      }
    }
  }

  public convenience init(
    port: NWEndpoint.Port = .any,
    localOnly: Bool = true,
    serviceName: String? = nil,
    serviceType: String? = nil,
    @RoutableBuilder routableBuilder: () -> Routable
  ) throws {
    try self.init(port: port, localOnly: localOnly, serviceName: serviceName, serviceType: serviceType)
    routableStorage = routableBuilder()
  }

}
