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
open class HTTPServer : NSObject {

  public enum Async : Swift.Error {
    case dispatch(() -> Void)
  }

  public typealias Dispatcher = (HTTPServer, HTTP.Request) throws -> HTTP.Response

  private let listener: NWListener
  private let queue = DispatchQueue(label: "HTTP Server Connection Queue", attributes: [.concurrent])
  private let mgrQueue = DispatchQueue(label: "HTTP Server Queue", attributes: [])
  private let dispatcher: Dispatcher
  private var connections = [String : HTTPConnection]()

  public var port: NWEndpoint.Port {
    return listener.port!
  }

  public private(set) var state: NWListener.State? = nil
  @objc public private(set) dynamic var isReady: Bool = false

  public init(port: NWEndpoint.Port = .any, localOnly: Bool = true, serviceName: String? = nil, dispatcher: @escaping Dispatcher) throws {
    self.dispatcher = dispatcher

    self.listener = try NWListener(using: .tcp, on: port)

    super.init()

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
      switch state {
      case .ready:
        self.isReady = true
      default:
        self.isReady = false
      }
    }

  }

  public func start(timeout: TimeInterval = 5) -> Bool {
    let sema = DispatchSemaphore(value: 0)

    let obs = observe(\.isReady, options: [.initial, .new]) { object, change in
      if change.newValue! {
        sema.signal()
      }
    }

    return withExtendedLifetime(obs) {

      listener.start(queue: queue)

      switch sema.wait(timeout: .now() + timeout) {
      case .success: return true
      case .timedOut: return false
      }

    }

  }

  func connect(with connection: NWConnection) {

    let httpConnection = HTTPConnection(server: self,
                                        transport: connection,
                                        dispatcher: self.dispatcher,
                                        log: logging.for(category: "HTTP Connection"))
    mgrQueue.sync {
      connections[httpConnection.id] = httpConnection
    }

    connection.stateUpdateHandler = { state in
      self.mgrQueue.sync {
        self.connections.removeValue(forKey: httpConnection.id)
      }
    }

    connection.start(queue: queue)
  }

}
