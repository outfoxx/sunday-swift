//
//  RoutingHTTPServer.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Network


open class RoutingHTTPServer: NetworkHTTPServer {

  private var _routable: Routable!

  open var routable: Routable {
    return _routable
  }

  public init(port: NWEndpoint.Port = .any, localOnly: Bool = true,
              serviceName: String? = nil, serviceType: String? = nil) throws {
    try super.init(port: port, localOnly: localOnly,
                   serviceName: serviceName, serviceType: serviceType) { request, response in
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

  public convenience init(port: NWEndpoint.Port = .any, localOnly: Bool = true,
                          serviceName: String? = nil, serviceType: String? = nil,
                          @RoutableBuilder routableBuilder: () -> Routable) throws {
    try self.init(port: port, localOnly: localOnly, serviceName: serviceName, serviceType: serviceType)
    _routable = routableBuilder()
  }

}
