//
//  File.swift
//  
//
//  Created by Kevin Wooten on 8/6/20.
//

import Foundation
import Combine


private let logger = logging.for(category: "event-publisher")


struct EventPublisher<Output: Decodable>: Publisher {
  
  public typealias Failure = Error
  
  private let requestor: (HTTP.Headers) -> AnyPublisher<URLSession.DataTaskStreamEvent, Swift.Error>
  private let decoder: MediaTypeDecoder
  
  public init(decoder: MediaTypeDecoder, queue: DispatchQueue, requestor: @escaping (HTTP.Headers) -> AnyPublisher<URLSession.DataTaskStreamEvent, Swift.Error>) {
    self.requestor = requestor
    self.decoder = decoder
  }
  
  public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
    let subscription = Subscription(parent: self, subscriber: subscriber)
    subscriber.receive(subscription: subscription)
  }
  
}

private extension EventPublisher {
  
  final class Subscription<S: Subscriber>: Combine.Subscription where S.Input == Output, S.Failure == Failure {
    
    private var lock = os_unfair_lock_s()
    private var parent: EventPublisher?
    private var subscriber: S?

    private var source: EventSource?
    private var demand: Subscribers.Demand = .none
    
    init(parent: EventPublisher, subscriber: S) {
      self.parent = parent
      self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
      os_unfair_lock_lock(&lock)
      defer {
        os_unfair_lock_unlock(&lock)
      }
      
      guard let parent = self.parent else {
        return
      }
      
      if source == nil {
        source = EventSource(requestor: parent.requestor)
        source!.onMessage(handleMessage(id:event:data:))
      }
      
      self.demand += demand

      source!.connect()
    }
    
    func handleMessage(id: String?, event: String?, data: String?) {
      os_unfair_lock_lock(&lock)
      defer {
        os_unfair_lock_unlock(&lock)
      }
    
      guard demand > 0, let parent = parent, let subscriber = self.subscriber else {
        return
      }
      
      // Convert "data" value to JSON
      guard let data = #"{"type": "\#(event ?? "")", "value": \#(data ?? "nil") }"#.data(using: .utf8) else {
        logger.error("Unable to parse event data")
        return
      }
      
      // Parse JSON and pass event on
      
      do {
        let event = try parent.decoder.decode(Output.self, from: data)
        
        demand += subscriber.receive(event)
      }
      catch {
        logger.error("Unable to decode event: \(error)")
        return
      }
    }
    
    func cancel() {
      os_unfair_lock_lock(&lock)
      defer {
        os_unfair_lock_unlock(&lock)
      }
      
      source?.close()
      
      parent = nil
      subscriber = nil
      source = nil
    }
    
  }
  
}
