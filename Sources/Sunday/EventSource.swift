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

// swiftlint:disable type_body_length

import Combine
import Foundation


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

  private static let maxRetryTimeMultiplier = 30


  public var readyState: State { readyStateValue.current }
  private var readyStateValue: StateValue

  public private(set) var retryTime = DispatchTimeInterval.milliseconds(500)

  private let requestor: (HTTP.Headers) -> AnyPublisher<NetworkSession.DataTaskStreamEvent, Swift.Error>
  private var dataCancel: AnyCancellable?
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
  private let eventTimeoutCheckInterval: DispatchTimeInterval
  private var eventTimeoutTask: DispatchWorkItem?

  private let eventParser = EventParser()


  public init(
    queue: DispatchQueue = .global(qos: .background),
    eventTimeoutInterval: DispatchTimeInterval? = DispatchTimeInterval.seconds(75),
    eventTimeoutCheckInterval: DispatchTimeInterval = DispatchTimeInterval.seconds(2),
    requestor: @escaping (HTTP.Headers) -> AnyPublisher<NetworkSession.DataTaskStreamEvent, Swift.Error>
  ) {
    self.queue = DispatchQueue(label: "io.outfoxx.sunday.EventSource", attributes: [], target: queue)
    readyStateValue = StateValue(.closed, queue: queue)
    self.requestor = requestor
    self.eventTimeoutInterval = eventTimeoutInterval
    self.eventTimeoutCheckInterval = eventTimeoutCheckInterval
    receivedString = nil
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

  open func addEventListener(
    _ event: String,
    handler: @escaping (_ event: String?, _ id: String?, _ data: String?) -> Void
  ) {
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
    if readyStateValue.isNotClosed {
      return
    }

    readyStateValue.update(forceTo: .connecting)

    internalConnect()
  }

  private func internalConnect() {

    guard readyStateValue.isNotClosed else {
      logger.debug("Skipping connect due to close")
      return
    }

    logger.debug("Connecting")

    // Build default headers for passing to request builder

    var headers = HTTP.Headers()
    headers[HTTP.StdHeaders.accept] = [MediaType.eventStream.value]

    // Add laste-event-id if we are reconnecting
    if let lastEventId = lastEventId {
      headers[HTTP.StdHeaders.lastEventId] = [lastEventId]
    }

    connectionAttemptTime = .now()

    dataCancel =
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
    logger.debug("Closed")

    readyStateValue.update(forceTo: .closed)

    internalClose()
  }

  private func internalClose() {

    dataCancel?.cancel()
    dataCancel = nil

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
    eventTimeoutTask = DispatchWorkItem { [weak self] in
      guard
        let strongSelf = self,
        let eventTimeoutTask = strongSelf.eventTimeoutTask,
        !eventTimeoutTask.isCancelled
      else {
        return
      }

      strongSelf.checkEventTimeout()

      if !eventTimeoutTask.isCancelled {
        strongSelf.queue.asyncAfter(deadline: .now() + strongSelf.eventTimeoutCheckInterval, execute: eventTimeoutTask)
      }
    }
    queue.asyncAfter(
      deadline: .now() + eventTimeoutCheckInterval,
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

    // If time has not expired, return
    guard DispatchTime.now() >= eventTimeoutDeadline else {
      return
    }

    logger.debug("Event Timeout Deadline Expired")

    fireErrorEvent(error: .eventTimeout)

    scheduleReconnect()
  }



  // MARK: Connection Handlers


  private func receivedHeaders(_ response: HTTPURLResponse) throws {

    guard readyStateValue.ifNotClosed(updateTo: .open) else {
      logger.error("invalid state for receiving headers: state=\(readyStateValue.current)")

      fireErrorEvent(error: .invalidState)

      scheduleReconnect()
      return
    }

    logger.debug("Opened")

    connectionOrigin = response.url
    retryAttempt = 0

    // Start event timeout check, treating this
    // connect as last time we received an event
    startEventTimeoutCheck(lastEventReceivedTime: .now())

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

    eventParser.process(data: data, dispatcher: dispatchParsedEvent)
  }

  private func receivedError(error: Swift.Error) {

    if readyStateValue.isClosed {
      return
    }

    logger.debug("Received Rrror \(error)")

    fireErrorEvent(error: error)

    if readyState != .closed {
      scheduleReconnect()
    }
  }

  private func receivedComplete() {

    if readyStateValue.isClosed {
      return
    }

    logger.debug("Received Complete")

    scheduleReconnect()
  }



  // MARK: Reconnection


  private func scheduleReconnect() {

    internalClose()

    guard readyStateValue.ifNotClosed(updateTo: .connecting) else {
      return
    }

    let lastConnectTime = connectionAttemptTime?.distance(to: .now()) ?? .microseconds(0)

    let retryDelay = Self.calculateRetryDelay(
      retryAttempt: retryAttempt,
      retryTime: retryTime,
      lastConnectTime: lastConnectTime
    )

    logger.debug("Scheduling Reconnect delay=\(retryDelay)")

    retryAttempt += 1

    reconnectTimeoutTask = DispatchWorkItem { [weak self] in
      guard
        let strongSelf = self,
        let reconnectTimeoutTask = strongSelf.reconnectTimeoutTask,
        !reconnectTimeoutTask.isCancelled
      else {
        return
      }

      strongSelf.internalConnect()
    }
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

    lastEventReceivedTime = .now()

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
    if info.event == nil, info.id == nil, info.data == nil {
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

  func fireErrorEvent(error: Error) {
    fireErrorEvent(error: error as Swift.Error)
  }

  func fireErrorEvent(error: Swift.Error) {

    if let onErrorCallback = onErrorCallback {
      queue.async { onErrorCallback(error) }
    }

  }

  struct StateValue {

    private var currentState: State
    private let queue: DispatchQueue

    init(_ initialState: State, queue: DispatchQueue) {
      currentState = initialState
      self.queue = queue
    }

    var current: State { queue.sync { currentState } }

    var isClosed: Bool { queue.sync { currentState == .closed } }
    var isNotClosed: Bool { queue.sync { currentState != .closed } }

    mutating func ifNotClosed(updateTo newState: State) -> Bool {
      return queue.sync {

        guard currentState != .closed else {
          return false
        }

        currentState = newState

        return true
      }
    }

    mutating func update(forceTo newState: State) {
      return queue.sync {
        currentState = newState
      }
    }

  }

}

public extension HTTP.StdHeaders {
  static let lastEventId = "Last-Event-Id"
}
