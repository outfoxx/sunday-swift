//
//  File.swift
//  
//
//  Created by Kevin Wooten on 7/8/19.
//

import Foundation
import Network


@available(macOS 10.14, iOS 13, tvOS 13, watchOS 6, *)
open class RoutingHTTPServer: NetworkHTTPServer {

  private var _routable: Routable!

  open var routable: Routable {
    return _routable
  }

  public init(port: NWEndpoint.Port = .any, localOnly: Bool = true, serviceName: String? = nil) throws {
    try super.init(port: port, localOnly: localOnly, serviceName: serviceName) { request, response in
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

  public convenience init(port: NWEndpoint.Port = .any, localOnly: Bool = true, serviceName: String? = nil,
                          @RoutableBuilder routableBuilder: () -> Routable) throws {
    try self.init(port: port, localOnly: localOnly, serviceName: serviceName)
    _routable = routableBuilder()
  }


}
