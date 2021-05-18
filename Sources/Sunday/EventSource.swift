//
//  EventSource.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


private let logger = logging.for(category: "Event Source")


open class EventSource {

  public enum Error: Swift.Error {
    case invalidState
    case eventTimeout
  }

  public enum State: String, CaseIterable {
    case connecting
    case open
    case closed
  }
  
  
  public static let eventTimeoutIntervalDefault = DispatchTimeInterval.seconds(75)
  private static let eventTimeoutCheckInterval = DispatchTimeInterval.seconds(2)
  private static let maxRetryTimeMultiplier = 30
  

  public private(set) var readyState = State.closed
  public private(set) var retryTime = DispatchTimeInterval.milliseconds(500)

  private let requestor: (HTTP.Headers) -> AnyPublisher<NetworkSession.DataTaskStreamEvent, Swift.Error>
  private var data$Cancel: AnyCancellable?
  private var receivedString: String?
  
  private var onOpenCallback: (() -> Void)?
  private var onErrorCallback: ((Swift.Error?) -> Void)?
  private var onMessageCallback: ((_ event: String?, _ id: String?, _ data: String?) -> Void)?
  private var eventListeners: [String: (_ event: String?, _ id: String?, _ data: String?) -> Void] = [:]
  
  private var queue: DispatchQueue

  private var lastEventId: String?
  private var lastEventReceivedTime: DispatchTime = .distantFuture

  private var connectionOrigin: URL?
  private var connectionAttemptTime: DispatchTime?
  private var reconnectTimeoutTask: DispatchWorkItem?
  private var retryAttempt = 0
  
  private let eventTimeoutInterval: DispatchTimeInterval?
  private var eventTimeoutTask: DispatchWorkItem?
  
  private let eventParser = EventParser()
  

  public init(queue: DispatchQueue = .global(qos: .background),
              eventTimeoutInterval: DispatchTimeInterval? = eventTimeoutIntervalDefault,
              requestor: @escaping (HTTP.Headers) -> AnyPublisher<NetworkSession.DataTaskStreamEvent, Swift.Error>) {

    self.requestor = requestor
    self.queue = queue
    self.eventTimeoutInterval = eventTimeoutInterval
    self.receivedString = nil
  }
  
  deinit {
    internalClose()
  }
  
  // MARK: EventListeners
  
  open func onOpen(_ onOpenCallback: @escaping () -> Void) {
    
    self.onOpenCallback = onOpenCallback
  }
  
  open func onError(_ onErrorCallback: @escaping (Swift.Error?) -> Void) {
    
    self.onErrorCallback = onErrorCallback
  }
  
  open func onMessage(_ onMessageCallback: @escaping (_ event: String?, _ id: String?, _ data: String?) -> Void) {
    self.onMessageCallback = onMessageCallback
  }
  
  open func addEventListener(_ event: String,
                             handler: @escaping (_ event: String?, _ id: String?, _ data: String?) -> Void) {
    eventListeners[event] = handler
  }
  
  open func removeEventListener(_ event: String) {
    eventListeners.removeValue(forKey: event)
  }
  
  open func events() -> [String] {
    return Array(eventListeners.keys)
  }

  
  
  // MARK: Connect

  open func connect() {
    if readyState == .connecting || readyState == .open {
      return
    }
    
    internalConnect()
  }
  
  private func internalConnect() {
    logger.debug("Connecting")
    
    readyState = .connecting
    
    // Build default headers for passing to request builder
    
    var headers = HTTP.Headers()
    headers[HTTP.StdHeaders.accept] = [MediaType.eventStream.value]
    
    // Add laste-event-id if we are reconnecting
    if let lastEventId = lastEventId {
      headers[HTTP.StdHeaders.lastEventId] = [lastEventId]
    }
    
    connectionAttemptTime = .now()
    
    data$Cancel =
      requestor(headers)
      .tryMap { event -> Void in
          switch event {
          case .connect(let response):
            try self.receivedHeaders(response)
          case .data(let data):
            try self.receivedData(data)
          }
        }
      .sink(receiveCompletion: { end in
        switch end {
        case .finished:
          self.receivedComplete()
        case .failure(let error):
          self.receivedError(error: error)
        }
      }, receiveValue: {})
  }

  
  
  // MARK: Close
  
  open func close() {
    logger.debug("Close Requested")

    readyState = .closed
    
    internalClose()
  }

  private func internalClose() {
    
    data$Cancel?.cancel()
    data$Cancel = nil
    
    cancelReconnect()
    
    stopEventTimeoutCheck()
  }
  
  
  
  // MARK: Event Timeout
  
  private func startEventTimeoutCheck(lastEventReceivedTime: DispatchTime) {
    
    stopEventTimeoutCheck()
    
    // If no timeout value, check is disabled
    guard eventTimeoutInterval != nil else {
      return
    }
    
    self.lastEventReceivedTime = lastEventReceivedTime
    
    // Schedule check
    eventTimeoutTask = DispatchWorkItem(block: checkEventTimeout)
    queue.asyncAfter(
      deadline: .now() + Self.eventTimeoutCheckInterval,
      execute: eventTimeoutTask!
    )
  }
  
  private func stopEventTimeoutCheck() {

    eventTimeoutTask?.cancel()
    eventTimeoutTask = nil
  }
  
  private func checkEventTimeout() {
    
    guard let eventTimeoutInterval = eventTimeoutInterval else {
      stopEventTimeoutCheck()
      return
    }
    
    logger.debug("Checking Event Timeout")
    
    let eventTimeoutDeadline = lastEventReceivedTime + eventTimeoutInterval
    let now = DispatchTime.now()
    guard now >= eventTimeoutDeadline else {
      return
    }
    
    logger.debug("Event Timeout Deadline Expired")
    
    fireErrorEvent(error: .eventTimeout)
      
    scheduleReconnect()
  }

  
  
  // MARK: Connection Handlers

  private func receivedHeaders(_ response: HTTPURLResponse) throws {
    
    guard readyState == .connecting else {
      logger.error("invalid state for receiving headers: state=\(readyState)")
      
      fireErrorEvent(error: .invalidState)

      scheduleReconnect()
      return
    }

    connectionOrigin = response.url
    retryAttempt = 0
    readyState = .open

    // Start event timeout check, treating this
    // connect as last time we received an event
    startEventTimeoutCheck(lastEventReceivedTime: .now())
    
    logger.debug("Opened")

    if let onOpenCallback = onOpenCallback {
      queue.async {
        onOpenCallback()
      }
    }
  }

  private func receivedData(_ data: Data) throws {
    
    guard readyState == .open else {
      logger.error("invalid state for receiving data: state=\(readyState)")

      fireErrorEvent(error: .invalidState)
      
      scheduleReconnect()
      return
    }

    logger.debug("Received Data count=\(data.count)")

    eventParser.process(data: data, dispatcher: self.dispatchParsedEvent)
  }

  private func receivedError(error: Swift.Error) {
    if readyState == .closed {
      return
    }

    logger.debug("Received Rrror \(error)")
    
    fireErrorEvent(error: error)
    
    if readyState != .closed {
      scheduleReconnect()
    }
  }

  private func receivedComplete() {
    if readyState == .closed {
      return
    }
    
    logger.debug("Received Complete")
    
    scheduleReconnect()
  }

  
  
  // MARK: Reconnection
  
  private func scheduleReconnect() {
    
    internalClose()
    
    let lastConnectTime = connectionAttemptTime?.distance(to: .now()) ?? .microseconds(0)
    
    let retryDelay = Self.calculateRetryDelay(retryAttempt: retryAttempt,
                                              retryTime: retryTime,
                                              lastConnectTime: lastConnectTime)
  
    logger.debug("Scheduling Reconnect delay=\(retryDelay)")
    
    retryAttempt += 1
    readyState = .connecting
    
    reconnectTimeoutTask = DispatchWorkItem(block: internalConnect)
    queue.asyncAfter(deadline: .now() + retryDelay, execute: reconnectTimeoutTask!)
  }
  
  private func cancelReconnect() {

    reconnectTimeoutTask?.cancel()
    reconnectTimeoutTask = nil
  }
  
  private static func calculateRetryDelay(
    retryAttempt: Int,
    retryTime: DispatchTimeInterval,
    lastConnectTime: DispatchTimeInterval
  ) -> DispatchTimeInterval {
    
    let retryAttempt = Double(retryAttempt)
    let retryTime = Double(retryTime.totalMilliseconds)
    
    // calculate total delay
    let backOffDelay = pow(retryAttempt, 2.0) * retryTime
    var retryDelay = min(
      retryTime + backOffDelay,
      retryTime * Double(Self.maxRetryTimeMultiplier)
    )
    
    // Adjust delay by amount of time last connect
    // cycle took, except on the first attempt
    if retryAttempt > 0 {
      
      retryDelay -= Double(lastConnectTime.totalMilliseconds)
      
      // Ensure delay is at least as large as
      // minimum retry time interval
      retryDelay = max(retryDelay, retryTime)
    }
    
    return .milliseconds(Int(retryDelay))
  }
  
  
  
  // MARK: Event Parsing

  private func dispatchParsedEvent(_ info: EventInfo) {
      
    // Update retry time if it's a valid integer
    if let retry = info.retry {
      
      if let retryTime = Int(retry.trimmingCharacters(in: .whitespaces), radix: 10) {
        logger.debug("update retry timeout: retryTime=\(retryTime)")

        self.retryTime = .milliseconds(retryTime)
        
      }
      else {
        logger.debug("ignoring invalid retry timeout message: retry=\(retry)")
      }
      
    }
    
    // Skip events without data
    if info.event == nil && info.id == nil && info.data == nil {
      // Skip empty events
      return
    }
    
    // Save event id, if it does not contain null
    if let eventId = info.id {
      // Check for NULL as it is not allowed
      if eventId.contains("\0") == false {

        lastEventId = eventId
      }
      else {        
        logger.debug("event id contains null, unable to use for last-event-id")
      }
    }

    lastEventReceivedTime = .now()

    if let onMessageCallback = onMessageCallback {

      logger.debug("dispatch onMessage: event=\(info.event ?? ""), id=\(info.id ?? "")")

      queue.async {
        onMessageCallback(info.event, info.id, info.data)
      }

    }

    if let event = info.event, let eventHandler = eventListeners[event] {

      logger.debug("dispatch listener: event=\(info.event ?? ""), id=\(info.id ?? "")")

      queue.async {
        eventHandler(event, info.id, info.data)
      }
    }

  }
  
  func fireErrorEvent(error: Error)  {
    fireErrorEvent(error: error as Swift.Error)
  }
  
  func fireErrorEvent(error: Swift.Error) {
    
    if let onErrorCallback = onErrorCallback {
      queue.async { onErrorCallback(error) }
    }

  }
  
}

extension HTTP.StdHeaders {
  public static let lastEventId = "Last-Event-Id"
}

fileprivate extension DispatchTimeInterval {
  
  var totalMilliseconds: Int {
    switch self {
    case .seconds(let secs): return secs * 1_000
    case .milliseconds(let millis): return millis
    case .microseconds(let micros): return micros / 1_000
    case .nanoseconds(let nanos): return nanos / 1_000_000
    default: return Int.max
    }
  }
  
  var totalSeconds: TimeInterval {
    switch self {
    case .seconds(let secs): return Double(secs) * 1_000.0
    case .milliseconds(let millis): return Double(millis)
    case .microseconds(let micros): return Double(micros) / 1_000.0
    case .nanoseconds(let nanos): return Double(nanos) / 1_000_000.0
    default: return TimeInterval.nan
    }
  }
  
}
