//
//  EventPublisher.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


private let logger = logging.for(category: "Event Publisher")


public struct EventPublisher<Output>: Publisher {
  
  public typealias Failure = Error
  
  private let requestor: (HTTP.Headers) -> AnyPublisher<NetworkSession.DataTaskStreamEvent, Swift.Error>
  private let decoder: TextMediaTypeDecoder
  private let eventTypes: [String: AnyTextMediaTypeDecodable]
  
  public init(
    eventTypes: [String: AnyTextMediaTypeDecodable],
    decoder: TextMediaTypeDecoder,
    queue: DispatchQueue,
    requestor: @escaping (HTTP.Headers) -> AnyPublisher<NetworkSession.DataTaskStreamEvent, Swift.Error>
  ) {
    self.requestor = requestor
    self.decoder = decoder
    self.eventTypes = eventTypes
  }
  
  public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
    let subscription = Subscription(parent: self, subscriber: subscriber)
    subscriber.receive(subscription: subscription)
  }
  
}

private extension EventPublisher {
  
  final class Subscription<S: Subscriber>: Combine.Subscription where S.Input == Output, S.Failure == Failure {
    
    private var lock = NSRecursiveLock()
    private var parent: EventPublisher?
    private var subscriber: S?

    private var source: EventSource?
    private var demand: Subscribers.Demand = .none
    
    init(parent: EventPublisher, subscriber: S) {
      self.parent = parent
      self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
      lock.lock()
      defer {
        lock.unlock()
      }
      
      guard let parent = self.parent else {
        return
      }
      
      if source == nil {
        source = EventSource(requestor: parent.requestor)
        source!.onMessage(handleMessage(event:id:data:))
      }
      
      self.demand += demand

      source!.connect()
    }
    
    func handleMessage(event: String?, id: String?, data: String?) {
      lock.lock()
      defer {
        lock.unlock()
      }

      guard demand > 0, let parent = parent, let subscriber = self.subscriber else {
        return
      }
      
      guard let eventType = parent.eventTypes[event ?? ""] else {
        logger.info("Unknown event type, ignoring event: type=\(event)")
        return
      }

      
      // Parse JSON and pass event on
      
      do {
        guard let event = try eventType.decode(parent.decoder, data ?? "") as? Output else {
          logger.error("Unable to decode event: no value returned")
          return
        }
        
        demand += subscriber.receive(event)
      }
      catch {
        logger.error("Unable to decode event: \(error)")
        return
      }
    }
    
    func cancel() {
      lock.lock()
      defer {
        lock.unlock()
      }

      source?.close()
      
      parent = nil
      subscriber = nil
      source = nil
    }
    
  }
  
}
