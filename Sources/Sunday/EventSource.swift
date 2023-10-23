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

import Foundation
import OSLog


private let logger = Logger.for(category: "EventSource")


/// `Sunday`'s implementation of the
/// [EventSource Web API](https://developer.mozilla.org/en-US/docs/Web/API/EventSource)
/// for connecting to servers that produce
/// [Server-Sent Events](https://html.spec.whatwg.org/multipage/server-sent-events.html).
///
/// ## HTTP Requests
///
/// `EventSource` allows HTTP requests to be generated asynchronously and
/// completely customized for each connection attempt.
///
/// Instead of providing a URL and having the `EventSource` handling the
/// building of HTTP requests internally, `Sunday`'s implementation delegates
/// this to an HTTP request factory method that returns a Combine `Publisher`
/// that must ultimately produce an HTTP request.
///
///
public class EventSource {

  public enum Error: Swift.Error {
    case invalidState
    case eventTimeout
    case requestStreamEmpty
  }

  /// Possible states of the `EventSource`
  public enum State: String, CaseIterable {

    /// Connection is being attempted.
    case connecting

    /// Connection has been opened and the
    /// EventSource` is receiving events.
    case open

    /// No connection is open and none is
    /// being attempted. This is the default
    /// state.
    case closed
  }

  /// Global default time interval for connection retries.
  ///
  ///
  /// - Important: The setting is mutable and can be modified to
  ///   alter the global default.
  ///
  /// - SeeAlso: `EventSource.retryTime`
  ///
  public static var retryTimeDefault = DispatchTimeInterval.milliseconds(100)

  /// Global default time interval for event timeout.
  ///
  /// If an event is not received within the specified timeout
  /// the connection is forcibly restarted.
  ///
  /// - Important: The setting is mutable and can be modified to
  /// alter the global default. If set to `nil`, the default will
  /// be that event timeouts are disabled. Each `EventSource` can
  /// override this setting in its initializer.
  ///
  public static var eventTimeoutIntervalDefault: DispatchTimeInterval? = DispatchTimeInterval.seconds(120)

  /// Global default time interval for event timeout checks.
  ///
  /// This setting controls the frequency that the event timeout
  /// is checked.
  ///
  /// - Important: The setting is mutable and can be modified to
  /// alter the global default. Each `EventSource` can override
  ///  this setting in its initializer.
  ///
  public static var eventTimeoutCheckIntervalDefault = DispatchTimeInterval.seconds(100)

  // Maximum multiplier for the backoff algorithm
  private static let maxRetryTimeMultiplier = 12
  private static let retryExponent = 2.6


  /// Current state of the `EventSource`.
  public var readyState: State { readyStateValue.current }
  private var readyStateValue: StateValue

  /// Current time interval for connection retries.
  ///
  /// The retry time defaults to the global default
  /// value `EventSource.retryTimeDefault`. It can also
  /// be updated by the server using retry update
  /// messages.
  ///
  /// - Note: EventSource employs an exponential backoff algorithm
  ///   for retries. This setting controls the initial retry delay
  ///   and calculations for successive retries.
  ///
  /// - SeeAlso: [Server-Sent Events](https://html.spec.whatwg.org/multipage/server-sent-events.html)
  ///
  public private(set) var retryTime = retryTimeDefault

  private let dataEventStreamFactory: (HTTP.Headers) async throws -> NetworkSession.DataEventStream?
  private var dataEventStreamTask: Task<Void, Swift.Error>?
  private var receivedString: String?

  private var onOpenCallback: (() -> Void)?
  private var onErrorCallback: ((Swift.Error?) -> Void)?
  private var onMessageCallback: ((_ event: String?, _ id: String?, _ data: String?) -> Void)?
  private var eventListeners: [String: [UUID: (_ event: String?, _ id: String?, _ data: String?) -> Void]] = [:]

  private var queue: DispatchQueue

  private var lastEventId: String?
  internal private(set) var lastEventReceivedTime: DispatchTime = .distantFuture

  private var connectionOrigin: URL?
  private var connectionAttemptTime: DispatchTime?
  private var reconnectTimeoutTask: DispatchWorkItem?
  private var retryAttempt = 0

  private let eventTimeoutInterval: DispatchTimeInterval?
  private let eventTimeoutCheckInterval: DispatchTimeInterval
  private var eventTimeoutTask: DispatchWorkItem?

  private let eventParser = EventParser()


  /// Creates an `EventSource` with the specific configuration.
  ///
  /// - Parameters:
  ///   - queue: Queue to use for dispatching events to handlers. Defaults to
  ///   the global background queue.
  ///
  ///   - eventTimeoutInterval: Maximum amount of time `EventSource` will wait for
  ///   an event before forcicbly reconnecting. Defaults to
  ///   `EventSource.eventTimeoutIntervalDefault`.
  ///
  ///   - eventTimeoutCheckInterval: Frequency that event timeouts are checked.
  ///   Defaults to `EventSource.eventTimeoutIntervalDefault`
  ///
  ///   - requestorFactory: Factory method for HTTP requests. It is provided
  ///   a map of HTTP headers that _should_ be included in the generated request
  ///   and returns a Combine `Publisher` that produces the HTTP request.
  ///
  public init(
    queue: DispatchQueue = .global(qos: .background),
    eventTimeoutInterval: DispatchTimeInterval? = eventTimeoutIntervalDefault,
    eventTimeoutCheckInterval: DispatchTimeInterval = eventTimeoutCheckIntervalDefault,
    dataEventStreamFactory: @escaping (HTTP.Headers) async throws -> NetworkSession.DataEventStream?
  ) {
    self.queue = DispatchQueue(label: "io.outfoxx.sunday.EventSource", attributes: [], target: queue)
    self.readyStateValue = StateValue(.closed, queue: queue)
    self.dataEventStreamFactory = dataEventStreamFactory
    self.eventTimeoutInterval = eventTimeoutInterval
    self.eventTimeoutCheckInterval = eventTimeoutCheckInterval
    self.receivedString = nil
  }

  deinit {
    internalClose()
  }



  // MARK: Event Handlers


  /// Handler to be called when the connection is opened.
  ///
  /// - Note: This _may_ be called multiple times. Each
  /// successful reconnection attempt will fire an open
  /// event.
  ///
  public var onOpen: (() -> Void)? {
    get { onOpenCallback }
    set { onOpenCallback = newValue }
  }

  /// Handler to be called when the connection experiences an
  /// error.
  ///
  /// - Note: This _may_ be called multiple times. Any
  /// interruption to an active connection will result in a
  /// an error event being fire; including for reconnections.
  ///
  public var onError: ((Swift.Error?) -> Void)? {
    get { onErrorCallback }
    set { onErrorCallback = newValue }
  }

  /// Handler to be called when any new event is received.
  ///
  public var onMessage: ((_ event: String?, _ id: String?, _ data: String?) -> Void)? {
    get { onMessageCallback }
    set { onMessageCallback = newValue }
  }

  /// Adds a new message handler for a specific type of event.
  ///
  /// - Parameters:
  ///   - event: Type of event to register the handler for.
  ///   - handler: Handler for received messages of type  event`.
  /// - Returns: Unique id of registered handler.
  ///
  @discardableResult
  public func addEventListener(
    for event: String,
    _ handler: @escaping (_ event: String?, _ id: String?, _ data: String?) -> Void
  ) -> UUID {
    queue.sync {
      let id = UUID()
      var handlers = eventListeners[event] ?? [:]
      handlers[id] = handler
      eventListeners[event] = handlers
      return id
    }
  }

  /// Adds a new message handler for a specific type of event.
  ///
  /// - Parameters:
  ///   - handlerId: Id of handler returned from `addEventListener`.
  ///   - handler: Handler for received messages of type  event`.
  ///
  public func removeEventListener(handlerId: UUID, for event: String) {
    queue.sync {
      guard var handlers = eventListeners[event] else {
        return
      }

      handlers.removeValue(forKey: handlerId)

      if handlers.isEmpty {
        eventListeners.removeValue(forKey: event)
      }
      else {
        eventListeners[event] = handlers
      }
    }
  }

  /// List of unique event types that handlers are
  /// registered for.
  ///
  public func registeredListenerTypes() -> [String] {
    queue.sync {
      return Array(eventListeners.keys)
    }
  }



  // MARK: Connect


  /// Opens a connection to the server.
  ///
  /// If the connection is already `open` or `connecting`, this does nothing.
  ///
  public func connect() {
    if readyStateValue.isNotClosed {
      return
    }

    readyStateValue.update(forceTo: .connecting)

    internalConnect()
  }

  private func internalConnect() {

    guard readyStateValue.isNotClosed else {
      #if EVENT_SOURCE_EXTRA_LOGGING
      logger.debug("Skipping connect due to close")
      #endif
      return
    }

    logger.debug("Connecting")

    connectionAttemptTime = .now()

    dataEventStreamTask = Task {

      // Build default headers for passing to request builder

      var headers = HTTP.Headers()
      headers[HTTP.StdHeaders.accept] = [MediaType.eventStream.value]

      // Add last-event-id if we are reconnecting
      if let lastEventId = self.lastEventId {
        headers[HTTP.StdHeaders.lastEventId] = [lastEventId]
      }

      // Create a data stream and
      do {

        guard let dataStream = try await dataEventStreamFactory(headers) else {
          logger.debug("Stream factory empty")
          fireErrorEvent(error: Error.requestStreamEmpty)
          close()
          return
        }

        for try await event in dataStream {

          switch event {
          case .connect(let response):
            try self.receivedHeaders(response)
          case .data(let data):
            try self.receivedData(data)
          }

        }

        self.receivedComplete()

      }
      catch {
        self.receivedError(error: error)
      }

    }
  }



  // MARK: Close


  /// Closes any current connection to the server.
  ///
  /// If the connection is not `open` or `connecting`, this does nothing.
  ///
  public func close() {
    logger.debug("Closed")

    readyStateValue.update(forceTo: .closed)

    internalClose()
  }

  private func internalClose() {

    dataEventStreamTask?.cancel()
    dataEventStreamTask = nil

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

    #if EVENT_SOURCE_EXTRA_LOGGING
    logger.debug("Checking Event Timeout")
    #endif

    let eventTimeoutDeadline = lastEventReceivedTime + eventTimeoutInterval

    // If time has not expired, return
    guard DispatchTime.now() >= eventTimeoutDeadline else {
      return
    }

    logger.debug("Event Timeout Deadline Expired")

    fireErrorEvent(error: Error.eventTimeout)

    scheduleReconnect()
  }



  // MARK: Connection Handlers


  private func receivedHeaders(_ response: HTTPURLResponse) throws {

    guard readyStateValue.ifNotClosed(updateTo: .open) else {
      logger.error("Invalid state for receiving headers: state=\(self.readyState.rawValue, privacy: .public)")

      fireErrorEvent(error: Error.invalidState)

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
      logger.error("Invalid state for receiving data: state=\(self.readyState.rawValue, privacy: .public)")

      fireErrorEvent(error: Error.invalidState)

      scheduleReconnect()
      return
    }

    logger.debug("Received Data: count=\(data.count)")

    eventParser.process(data: data, dispatcher: dispatchParsedEvent)
  }

  private func receivedError(error: Swift.Error) {

    if readyStateValue.isClosed {
      return
    }

    // Quietly close dure to Task or URLTask cancellation
    if isCancellationError(error: error) {
      fireErrorEvent(error: error)
      close()
      return
    }

    logger.debug("Received Error: \(error.localizedDescription, privacy: .public)")

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

  private func isCancellationError(error: Swift.Error) -> Bool {
    switch error {
    case let urlError as URLError where urlError.code == .cancelled: return true
    case is CancellationError: return true
    default: return false
    }
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

    logger.debug("Scheduling Reconnect delay=\(retryDelay.totalSeconds, format: .fixed(precision: 3))")

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

  static func calculateRetryDelay(
    retryAttempt: Int,
    retryTime: DispatchTimeInterval,
    lastConnectTime: DispatchTimeInterval
  ) -> DispatchTimeInterval {

    let retryMultiplier = Double(min(retryAttempt, Self.maxRetryTimeMultiplier))
    let retryTime = Double(retryTime.totalMilliseconds)

    // calculate total delay
    var retryDelay = pow(retryMultiplier, retryExponent) * retryTime

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
        logger.debug("Update retry timeout: retryTime=\(retryTime)ms")

        self.retryTime = .milliseconds(retryTime)

      }
      else {
        logger.debug("Ignoring invalid retry timeout message: retry=\(retry, privacy: .public)")
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
      if !eventId.contains("\0") {

        lastEventId = eventId
      }
      else {
        logger.debug("Event id contains null, unable to use for last-event-id")
      }
    }

    if let onMessageCallback = onMessageCallback {

      logger.debug(
        "Dispatch onMessage: event=\(info.event ?? "", privacy: .public), id=\(info.id ?? "", privacy: .public)"
      )

      queue.async {
        onMessageCallback(info.event, info.id, info.data)
      }

    }

    queue.async {

      if let event = info.event, let eventHandlers = self.eventListeners[event] {

        for eventHandler in eventHandlers {

          logger.debug(
            "Dispatch listener: event=\(info.event ?? "", privacy: .public), id=\(info.id ?? "", privacy: .public)"
          )

          eventHandler.value(event, info.id, info.data)
        }
      }
    }

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
