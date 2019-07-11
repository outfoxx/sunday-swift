//
//  File.swift
//  
//
//  Created by Kevin Wooten on 7/8/19.
//

import Foundation
import Network


@available(macOS 10.14, iOS 13, tvOS 13, watchOS 6, *)
open class RoutingHTTPServer: HTTPServer {

  private var _routable: Routable!

  open var routable: Routable {
    return _routable
  }

  public init(port: NWEndpoint.Port = .any, localOnly: Bool = true, serviceName: String? = nil) throws {
    try super.init(port: port, localOnly: localOnly, serviceName: serviceName) { server, request in
      let server = server as! RoutingHTTPServer
      do {
        let variables: [String: Any] = ["@server": server]
        guard let response = try server.routable.route(request: request, path: request.url.path, variables: variables) else {
          return .notFound(message: "No method handler found")
        }
        return response
      }
      catch {
        return .internalServerError(message: String(describing: error))
      }
    }
  }

  public convenience init(port: NWEndpoint.Port = .any, localOnly: Bool = true, serviceName: String? = nil,
                          @RoutableBuilder routableBuilder: () -> Routable) throws {
    try self.init(port: port, localOnly: localOnly, serviceName: serviceName)
    _routable = routableBuilder()
  }


}
