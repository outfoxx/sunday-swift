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
  private var onMessageCallback: ((String?, String?, String?) -> Void)?
  private var eventListeners = [String: (String?, String?, String?) -> Void]()
  
  private var queue: DispatchQueue

  private var receivedDataBuffer: Data
  private var lastEventId: String?
  private var lastEventReceivedTime: DispatchTime = .distantFuture

  private var connectionAttemptTime: DispatchTime?
  private var reconnectTimeoutTask: DispatchWorkItem?
  private var retryAttempt = 0
  
  private let eventTimeoutInterval: DispatchTimeInterval?
  private var eventTimeoutTask: DispatchWorkItem?
  

  public init(queue: DispatchQueue = .global(qos: .background),
              eventTimeoutInterval: DispatchTimeInterval? = eventTimeoutIntervalDefault,
              requestor: @escaping (HTTP.Headers) -> AnyPublisher<NetworkSession.DataTaskStreamEvent, Swift.Error>) {

    self.requestor = requestor
    self.queue = queue
    self.eventTimeoutInterval = eventTimeoutInterval
    self.receivedString = nil
    self.receivedDataBuffer = Data()
  }
  
  // MARK: EventListeners
  
  open func onOpen(_ onOpenCallback: @escaping () -> Void) {
    
    self.onOpenCallback = onOpenCallback
  }
  
  open func onError(_ onErrorCallback: @escaping (Swift.Error?) -> Void) {
    
    self.onErrorCallback = onErrorCallback
  }
  
  open func onMessage(_ onMessageCallback: @escaping (_ id: String?, _ event: String?, _ data: String?) -> Void) {
    self.onMessageCallback = onMessageCallback
  }
  
  open func addEventListener(_ event: String,
                             handler: @escaping (_ id: String?, _ event: String?, _ data: String?) -> Void) {
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
    
    data$Cancel = requestor(headers)
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
    if eventTimeoutInterval == nil {
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
      return
    }
    
    logger.debug("Checking Event Timeout")
    
    let eventTimeoutDeadline = lastEventReceivedTime + eventTimeoutInterval
    guard DispatchTime.now() < eventTimeoutDeadline else {
      return
    }
    
    logger.debug("Event Timeout Deadline Expired")
      
    internalClose()
    scheduleReconnect()
  }

  // MARK: Handlers

  private func receivedHeaders(_ response: HTTPURLResponse) throws {
    guard readyState == .connecting else {
      logger.error("invalid state for receiving headers: state=\(readyState)")
      
      internalClose()
      scheduleReconnect()
      return
    }

    retryAttempt = 0
    readyState = .open

    // Start event timeout check, treating this
    // connect as last time we received an event
    startEventTimeoutCheck(lastEventReceivedTime: .now())
    
    logger.debug("Opened")

    onOpenCallback.flatMap { queue.async(execute: $0) }
  }

  private func receivedData(_ data: Data) throws {
    guard readyState == .open else {
      logger.error("invalid state for receiving data: state=\(readyState)")

      internalClose()
      scheduleReconnect()
      return
    }

    guard !data.isEmpty else {
      return
    }

    logger.debug("Received data, count=\(data.count)")

    receivedDataBuffer.append(data)

    let eventStrings = extractEventStringsFromBuffer()
    parseEventStrings(eventStrings)
  }

  private func receivedError(error: Swift.Error) {

    // Ensure this is _not_ a cancellation
    guard (error as? URLError)?.code != .cancelled else {
      return
    }

    logger.debug("Error: \(error)")

    scheduleReconnect()

    if let onErrorCallback = onErrorCallback {
        queue.async { onErrorCallback(error) }
    }
  }

  private func receivedComplete() {
    
    if readyState != .closed {
      
      logger.debug("Unexpected Completion")

      scheduleReconnect()
      
      return
    }

    logger.debug("Closing")

    return
  }

  // MARK: Reconnection
  
  private func scheduleReconnect() {
    
    let lastConnectTime = connectionAttemptTime?.distance(to: .now()) ?? .microseconds(0)
    
    let retryDelay = Self.calculateRetryDelay(retryAttempt: retryAttempt,
                                              retryTime: retryTime,
                                              lastConnectTime: lastConnectTime)
  
    logger.debug("Scheduling Reconnect delay=\(retryDelay)")
    
    retryAttempt += 1
    
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

  private func extractEventStringsFromBuffer() -> [String] {

    var eventStrings = [String]()

    // Find first occurrence of delimiter
    var searchRange: Range<Int> = 0 ..< receivedDataBuffer.count
    while let delimterRange = searchForSeparatorInRange(searchRange) {

      let dataRange = Range(uncheckedBounds: (searchRange.lowerBound, delimterRange.upperBound))

      let dataChunk = receivedDataBuffer.subdata(in: dataRange)

      eventStrings.append(String(data: dataChunk, encoding: .utf8)!)

      // Search for next occurrence of delimiter
      searchRange = Range(uncheckedBounds: (delimterRange.upperBound, searchRange.upperBound))
    }

    // Remove the found events from the buffer
    receivedDataBuffer.replaceSubrange(0 ..< searchRange.lowerBound, with: Data())

    return eventStrings
  }

  private func searchForSeparatorInRange(_ searchRange: Range<Int>) -> Range<Int>? {

    for delimiter in validSeparatorSequences {

      if let foundRange = receivedDataBuffer.range(of: delimiter, options: [], in: searchRange) {
        return foundRange
      }

    }

    return nil
  }

  private func parseEventStrings(_ eventStrings: [String]) {

    for eventString in eventStrings {
      if eventString.isEmpty {
        continue
      }

      let parsedEvent = parseEvent(eventString)
      
      if let retry = parsedEvent.retry {
        
        guard parsedEvent.data == nil, parsedEvent.id == nil, parsedEvent.event == nil else {
          logger.debug("ignoring invalid retry timeout message")
          continue
        }
        
        let updatedRetryTime = Int(retry.trimmingCharacters(in: .whitespaces)).map { DispatchTimeInterval.milliseconds($0) }
        self.retryTime = updatedRetryTime ?? self.retryTime
      }
      
      lastEventId = parsedEvent.id ?? lastEventId

      if let data = parsedEvent.data, let onMessage = onMessageCallback {

        logger.debug("onMessage: event=\(parsedEvent.event ?? ""), id=\(parsedEvent.id ?? "")")

        queue.async {
          onMessage(self.lastEventId, parsedEvent.event, data)
        }

      }

      if let event = parsedEvent.event, let data = parsedEvent.data, let eventHandler = eventListeners[event] {

        logger.debug("listener: event=\(parsedEvent.event ?? ""), id=\(parsedEvent.id ?? "")")

        queue.async {
          eventHandler(self.lastEventId, event, data)
        }
      }
    }
  }

  private func parseEvent(_ eventString: String) -> (id: String?, event: String?, data: String?, retry: String?) {

    var id: String?
    var event: String?
    var data: String?
    var retry: String?

    for line in eventString.components(separatedBy: .newlines) {

      let fields = line.split(separator: ":", maxSplits: 1)
      guard !fields.isEmpty else {
        continue
      }
      
      let key = fields[0]
      var value = fields.count == 2 ? String(fields[1]) : ""
      
      if value.first == " " {
        value = String(value.dropFirst())
      }

      switch key {
      case "id":
        id = value
      case "event":
        event = value
      case "data":
        if let cur = data {
          data = cur + "\n" + value
        }
        else {
          data = value
        }
      case "retry":
        retry = value
      default:
        break
      }
    }

    return (id, event, data, retry)
  }
  
}


private let validNewlines = ["\r\n", "\n", "\r"]
private let validSeparatorSequences = validNewlines.map { "\($0)\($0)".data(using: .utf8)! }

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
  
}
