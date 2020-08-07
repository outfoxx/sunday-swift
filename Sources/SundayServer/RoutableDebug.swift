//
//  RoutableDebug.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

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
