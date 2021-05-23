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



public class ServiceLocator: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

  public static func locate(
    instance: String?,
    type: String,
    domain: String = "",
    timeout: TimeInterval = 20.0
  ) -> Service? {
    let sema = DispatchSemaphore(value: 0)
    let locator = ServiceLocator(instance: instance, type: type, domain: domain) { sema.signal() }
    guard sema.wait(timeout: .now() + .milliseconds(Int(timeout * 1000))) == .success else {
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

    browser = NetServiceBrowser()

    super.init()

    browser.delegate = self
    browser.searchForServices(ofType: type, inDomain: domain)

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
