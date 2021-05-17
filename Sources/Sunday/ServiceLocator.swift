//
//  ServiceLocator.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation



public class ServiceLocator: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

  public static func locate(instance: String?, type: String, domain: String = "",
                            timeout: TimeInterval = 20.0) -> Service? {
    let sema = DispatchSemaphore(value: 0)
    let locator = ServiceLocator(instance: instance, type: type, domain: domain) { sema.signal() }
    guard sema.wait(timeout: .now() + .milliseconds(Int(timeout * 1_000))) == .success else {
      return nil
    }
    return locator.located.first!
  }

  public struct Service: Equatable {
    public let hostName: String
    public let port: Int
  }

  public typealias Signal = () -> Void

  public var located: [Service] = []

  private let instance: String?

  private let signal: Signal
  private let browser: NetServiceBrowser

  private var resolving: [NetService] = []

  public init(instance: String?, type: String, domain: String = "", signal: @escaping Signal = {}) {
    self.instance = instance
    self.signal = signal

    self.browser = NetServiceBrowser()

    super.init()

    self.browser.delegate = self
    self.browser.searchForServices(ofType: type, inDomain: domain)

    Thread.detachNewThread {
      self.browser.schedule(in: RunLoop.current, forMode: .default)
      RunLoop.current.run()
    }
  }

  public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {

    if instance == nil || instance == service.name {

      resolving.append(service)

      service.delegate = self

      service.resolve(withTimeout: 0.0)
    }

  }

  public func netServiceDidResolveAddress(_ sender: NetService) {

    resolving.removeAll { $0 == sender }

    located.append(Service(hostName: sender.hostName ?? "localhost", port: sender.port))

    sender.stop()

    signal()
  }

  public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {

    located.removeAll { $0 == Service(hostName: service.hostName ?? "localhost", port: service.port) }
  }

}
