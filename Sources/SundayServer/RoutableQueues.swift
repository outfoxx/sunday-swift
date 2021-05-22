//
//  RoutableQueues.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public struct RunOn: Routable {

  let queue: DispatchQueue
  let routable: Routable

  public init(queue: DispatchQueue, @RoutableBuilder routableBuilder: () -> Routable) {
    self.queue = queue
    routable = routableBuilder()
  }

  public func route(_ route: SundayServer.Route, request: HTTPRequest) throws -> RouteResult? {
    guard let routed = try routable.route(route, request: request) else {
      return nil
    }
    let handler: RouteHandler = { route, request, response in
      try self.queue.sync {
        try routed.handler(route, request, response)
      }
    }
    return (routed.route, handler)
  }

}
