//
//  HTTPServer.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/16/19.
//  Copyright © 2019 Outfox, Inc. All rights reserved.
//

import Foundation
import Network
import Sunday
import RxSwift


@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
public class HTTPServer {

  public typealias Dispatcher = (HTTP.Request) throws -> HTTP.Response

  private let listener: NWListener
  private let queue = DispatchQueue(label: "HTTP Server Connection Queue")
  private let dispatcher: Dispatcher
  private var connections = [String : HTTPConnection]()

  public var port: NWEndpoint.Port {
    return listener.port!
  }

  public private(set) var state: NWListener.State? = nil

  public init(port: NWEndpoint.Port = 8080, serviceName: String? = nil, localOnly: Bool = false, dispatcher: @escaping Dispatcher) throws {
    self.dispatcher = dispatcher

    listener = try NWListener(using: .tcp, on: port)

    if let serviceName = serviceName {
      listener.service = NWListener.Service(name: serviceName, type: "_http._tcp")
    }
    listener.parameters.acceptLocalOnly = localOnly

    listener.newConnectionHandler = { [weak self] connection in
      guard let self = self else { return }
      self.connect(with: connection)
    }

    listener.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      self.queue.async {
        self.state = state
      }
    }

    listener.start(queue: queue)
  }

  func connect(with connection: NWConnection) {

    let httpConnection = HTTPConnection(server: self,
                                        transport: connection,
                                        dispatcher: self.dispatcher,
                                        log: logging.for(category: "HTTP Connection"))
    connections[httpConnection.id] = httpConnection

    connection.stateUpdateHandler = { state in
      self.connections.removeValue(forKey: httpConnection.id)
    }

    connection.start(queue: queue)
  }

  public func waitForReady() {
    while self.queue.sync(execute: { return self.state }) != .ready {}
  }

}

@available(macOS 10.14, iOS 13, tvOS 13, watchOS 6, *)
extension HTTPServer {

  public convenience init(port: NWEndpoint.Port = .any, serviceName: String? = nil, localOnly: Bool = true, @RoutableBuilder _ buildRoutable: () -> Routable) throws {
    let routable = buildRoutable()
    try self.init(port: port, serviceName: serviceName, localOnly: localOnly, dispatcher: { request in
      do {
        guard let response = try routable.route(request: request, path: request.url.path, variables: [:]) else {
          return .notFound(message: "No method handler found")
        }
        return response
      }
      catch {
        return .internalServerError(message: String(describing: error))
      }
    })
  }

}
