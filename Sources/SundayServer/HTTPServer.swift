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


public protocol HTTPServer: AnyObject {

  typealias Dispatcher = (HTTPRequest, HTTPResponse) throws -> Void

  var queue: DispatchQueue { get }

}


open class NetworkHTTPServer: NSObject, HTTPServer {

  public let queue = DispatchQueue(label: "HTTP Server Connection Queue", attributes: [.concurrent])

  private let listener: NWListener
  private let mgrQueue = DispatchQueue(label: "HTTP Server Queue", attributes: [])
  private let dispatcher: Dispatcher
  private var connections = [String: NetworkHTTPConnection]()

  public private(set) var state: NWListener.State?
  @objc public private(set) dynamic var isReady: Bool = false

  public init(
    port: NWEndpoint.Port = .any,
    localOnly: Bool = true,
    serviceName: String? = nil,
    serviceType: String? = nil,
    dispatcher: @escaping Dispatcher
  ) throws {
    self.dispatcher = dispatcher

    listener = try NWListener(using: .tcp, on: port)

    super.init()

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

    if let serviceType = serviceType {
      let serviceName = serviceName ?? String(format: "%qx", UInt64.random(in: 0 ... UInt64.max))
      listener.service = NWListener.Service(name: serviceName, type: serviceType)
    }

  }

  @available(iOS 14, tvOS 14, macOS 11, *)
  @available(watchOS, unavailable)
  public func start(timeout: TimeInterval = 30) -> URL? {

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

    starter.enter()
    let obs = observe(\.isReady, options: [.initial, .new]) { _, change in
      if change.newValue! {
        starter.leave()
      }
    }

    return withExtendedLifetime(obs) {

      listener.start(queue: queue)

      switch starter.wait(timeout: .now() + timeout) {
      case .success:
        return locator?.located.first.flatMap { URL(string: "http://\($0.hostName):\($0.port)") } ??
          URL(string: "http://localhost:\(listener.port!)")!

      case .timedOut:
        return nil
      }

    }

  }

  public func startLocal(timeout: TimeInterval = 30) -> URL? {

    let starter = DispatchGroup()

    starter.enter()
    let obs = observe(\.isReady, options: [.initial, .new]) { _, change in
      if change.newValue! {
        starter.leave()
      }
    }

    return withExtendedLifetime(obs) {

      listener.start(queue: queue)

      switch starter.wait(timeout: .now() + timeout) {
      case .success:
        return URL(string: "http://localhost:\(listener.port!)")!

      case .timedOut:
        return nil
      }

    }

  }

  public func stop() {
    listener.cancel()
  }

  func connect(with connection: NWConnection) {

    let httpConnection = NetworkHTTPConnection(
      transport: connection,
      server: self,
      id: UUID().uuidString,
      logger: Logger.for(category: "HTTP Connection"),
      dispatcher: dispatcher
    )

    mgrQueue.sync {
      connections[httpConnection.id] = httpConnection
    }

    connection.stateUpdateHandler = { _ in
      self.mgrQueue.sync {
        self.connections.removeValue(forKey: httpConnection.id)
      }
    }

    connection.start(queue: queue)
  }

}
