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
import OSLog
import Sunday
import Synchronization


public final class RoutingHTTPServer: NSObject, HTTPServer, Sendable {

  private struct State {
    var listenerState: NWListener.State?
    var isReady = false
    var readySignaled = false
  }

  public let queue = DispatchQueue(label: "HTTP Server Connection Queue", attributes: [.concurrent])

  private let listener: NWListener
  private let dispatcher: Dispatcher
  private let routableStorage: Routable
  private let stateStorage = Mutex(State())
  private let connections = Mutex<[String: HTTPConnection]>([:])
  private let readyGroup = DispatchGroup()

  public var routable: Routable {
    return routableStorage
  }

  public var state: NWListener.State? {
    return stateStorage.withLock { $0.listenerState }
  }

  public var isReady: Bool {
    return stateStorage.withLock { $0.isReady }
  }

  public convenience init(
    port: NWEndpoint.Port = .any,
    localOnly: Bool = true,
    serviceName: String? = nil,
    serviceType: String? = nil
  ) throws {
    try self.init(port: port, localOnly: localOnly, serviceName: serviceName, serviceType: serviceType) {
      EmptyRoutable()
    }
  }

  public init(
    port: NWEndpoint.Port = .any,
    localOnly: Bool = true,
    serviceName: String? = nil,
    serviceType: String? = nil,
    @RoutableBuilder routableBuilder: () -> Routable
  ) throws {
    routableStorage = routableBuilder()

    dispatcher = { request, response in
      guard let routingServer = request.server as? RoutingHTTPServer else {
        response.send(status: .internalServerError, text: "Invalid routing server")
        return
      }

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

    listener = try NWListener(using: .tcp, on: port)
    readyGroup.enter()

    super.init()

    listener.parameters.acceptLocalOnly = localOnly
    listener.newConnectionHandler = { [weak self] connection in
      self?.connect(with: connection)
    }
    listener.stateUpdateHandler = { [weak self] state in
      self?.update(state: state)
    }

    if let serviceType = serviceType {
      let serviceName = serviceName ?? String(format: "%qx", UInt64.random(in: 0 ... UInt64.max))
      listener.service = NWListener.Service(name: serviceName, type: serviceType)
    }
  }

  @available(iOS 14, tvOS 14, macOS 11, *)
  @available(watchOS, unavailable)
  public func start(timeout: TimeInterval = 30) -> URL? {

    guard canStartListener() else {
      return nil
    }

    let deadline = DispatchTime.now() + timeout
    let starter = DispatchGroup()

    let locator: ServiceLocator?
    if let service = listener.service {

      starter.enter()

      locator = ServiceLocator(
        instance: service.name ?? "",
        type: service.type,
        domain: service.domain ?? "",
        signal: { starter.leave() }
      )
    }
    else {

      locator = nil
    }

    listener.start(queue: queue)

    guard waitForReady(deadline: deadline) else {
      return nil
    }

    if starter.wait(timeout: deadline) == .timedOut {
      return nil
    }

    guard let port = listener.port else {
      return nil
    }

    return locator?.located.first.flatMap { URL(string: "http://\($0.hostName):\($0.port)") } ??
      URL(string: "http://localhost:\(port)")
  }

  public func startLocal(timeout: TimeInterval = 30) -> URL? {

    guard canStartListener() else {
      return nil
    }

    listener.start(queue: queue)

    guard waitForReady(deadline: DispatchTime.now() + timeout) else {
      return nil
    }

    guard let port = listener.port else {
      return nil
    }

    return URL(string: "http://localhost:\(port)")
  }

  public func stop() {
    if recordTerminalState(.cancelled) {
      readyGroup.leave()
    }

    listener.cancel()
    connections.withLock { connections in
      connections.values.forEach { $0.close() }
      connections.removeAll()
    }
  }

  private func canStartListener() -> Bool {
    return stateStorage.withLock { storedState in
      switch storedState.listenerState {
      case .cancelled?, .failed?:
        return false
      default:
        return true
      }
    }
  }

  private func waitForReady(deadline: DispatchTime) -> Bool {
    return readyGroup.wait(timeout: deadline) == .success && isReady
  }

  private func update(state: NWListener.State) {
    if recordTerminalState(state) {
      readyGroup.leave()
    }
  }

  private func recordTerminalState(_ state: NWListener.State) -> Bool {
    return stateStorage.withLock { storedState in
      storedState.listenerState = state
      storedState.isReady = state == .ready
      let isTerminal =
        switch state {
        case .ready, .failed, .cancelled: true
        default: false
        }
      guard isTerminal, !storedState.readySignaled else {
        return false
      }
      storedState.readySignaled = true
      return true
    }
  }

  private func connect(with connection: NWConnection) {

    let httpConnection = HTTPConnection(
      transport: connection,
      server: self,
      id: UUID().uuidString,
      logger: Logger.for(category: "HTTP Connection"),
      dispatcher: dispatcher
    )

    connections.withLock { connections in
      connections[httpConnection.id] = httpConnection
    }

    let connectionId = httpConnection.id
    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .cancelled, .failed:
        break
      default:
        return
      }
      _ = self?.connections.withLock { connections in
        connections.removeValue(forKey: connectionId)
      }
    }

    connection.start(queue: queue)
  }

}


private struct EmptyRoutable: Routable {

  func route(_ route: Route, request: HTTPRequest) throws -> RouteResult? {
    return nil
  }

}
