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
import OSLog
import Synchronization


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
/// this to a data-event stream factory.
///
public actor EventSource { // swiftlint:disable:this type_body_length

  /// Handler to receive an event source message.
  public typealias EventHandler = @Sendable (_ event: String?, _ id: String?, _ data: String?) -> Void

  public enum Error: Swift.Error {
    case invalidState
    case eventTimeout
    case requestStreamEmpty
  }

  /// Possible states of the `EventSource`.
  public enum State: String, CaseIterable, Sendable {

    /// Connection is being attempted.
    case connecting

    /// Connection has been opened and the `EventSource` is receiving events.
    case open

    /// No connection is open and none is being attempted.
    case closed
  }

  typealias StateErrorHandler = @Sendable (_ error: Swift.Error?, _ readyState: State) -> Void

  /// Global default time interval for connection retries.
  ///
  /// - Important: The setting is mutable and can be modified to alter the global default.
  ///
  /// - SeeAlso: `EventSource.retryTime`
  ///
  public static var retryTimeDefault: DispatchTimeInterval {
    get { eventSourceDefaults.withLock { $0.retryTime } }
    set { eventSourceDefaults.withLock { $0.retryTime = newValue } }
  }

  /// Global default time interval for event timeout.
  ///
  /// If an event is not received within the specified timeout the connection is forcibly restarted.
  ///
  /// - Important: The setting is mutable and can be modified to alter the global default. If set to
  ///   `nil`, the default will be that event timeouts are disabled. Each `EventSource` can override
  ///   this setting in its initializer.
  ///
  public static var eventTimeoutIntervalDefault: DispatchTimeInterval? {
    get { eventSourceDefaults.withLock { $0.eventTimeoutInterval } }
    set { eventSourceDefaults.withLock { $0.eventTimeoutInterval = newValue } }
  }

  /// Global default time interval for event timeout checks.
  ///
  /// This setting controls the frequency that the event timeout is checked.
  ///
  /// - Important: The setting is mutable and can be modified to alter the global default. Each
  ///   `EventSource` can override this setting in its initializer.
  ///
  public static var eventTimeoutCheckIntervalDefault: DispatchTimeInterval {
    get { eventSourceDefaults.withLock { $0.eventTimeoutCheckInterval } }
    set { eventSourceDefaults.withLock { $0.eventTimeoutCheckInterval = newValue } }
  }

  // Maximum multiplier for the backoff algorithm.
  private static let maxRetryTimeMultiplier = 12
  private static let retryExponent = 2.6


  /// Current state of the `EventSource`.
  public private(set) var readyState = State.closed

  /// Current time interval for connection retries.
  ///
  /// The retry time defaults to the global default value `EventSource.retryTimeDefault`. It can also
  /// be updated by the server using retry update messages.
  ///
  /// - Note: EventSource employs an exponential backoff algorithm for retries. This setting controls
  ///   the initial retry delay and calculations for successive retries.
  ///
  /// - SeeAlso: [Server-Sent Events](https://html.spec.whatwg.org/multipage/server-sent-events.html)
  ///
  public private(set) var retryTime = retryTimeDefault

  internal private(set) var lastEventReceivedTime = DispatchTime.distantFuture

  private let callbackQueue: DispatchQueue
  private let dataEventStreamFactory: @Sendable (HTTP.Headers) async throws -> URLSession.DataEventStream?

  private var onOpen: (@Sendable () -> Void)?
  private var onError: (@Sendable (Swift.Error?) -> Void)?
  private var onStateError: StateErrorHandler?
  private var onMessage: EventHandler?
  private var eventListeners: [String: [UUID: EventHandler]] = [:]

  private var lastEventId: String?
  private var connectionAttemptTime: DispatchTime?
  private var retryAttempt = 0

  private let eventTimeoutInterval: DispatchTimeInterval?
  private let eventTimeoutCheckInterval: DispatchTimeInterval

  private var dataEventStreamTask: Task<Void, Never>?
  private var queuedReconnectTask: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private var eventTimeoutTask: Task<Void, Never>?

  private let eventParser = EventParser()


  /// Creates an `EventSource` with the specific configuration.
  ///
  /// - Parameters:
  ///   - queue: Queue to use for dispatching events to handlers. Defaults to the global default
  ///     queue.
  ///   - eventTimeoutInterval: Maximum amount of time `EventSource` will wait for an event before
  ///     forcibly reconnecting. Defaults to `EventSource.eventTimeoutIntervalDefault`.
  ///   - eventTimeoutCheckInterval: Frequency that event timeouts are checked. Defaults to
  ///     `EventSource.eventTimeoutIntervalDefault`.
  ///   - dataEventStreamFactory: Factory method for data event streams. It is provided a map of HTTP
  ///     headers that should be included in the generated request.
  ///
  public init(
    queue: DispatchQueue = .global(qos: .default),
    eventTimeoutInterval: DispatchTimeInterval? = eventTimeoutIntervalDefault,
    eventTimeoutCheckInterval: DispatchTimeInterval = eventTimeoutCheckIntervalDefault,
    dataEventStreamFactory: @escaping @Sendable (HTTP.Headers) async throws -> URLSession.DataEventStream?
  ) {
    self.callbackQueue = DispatchQueue(label: "io.outfoxx.sunday.EventSource", target: queue)
    self.dataEventStreamFactory = dataEventStreamFactory
    self.eventTimeoutInterval = eventTimeoutInterval
    self.eventTimeoutCheckInterval = eventTimeoutCheckInterval
  }

  deinit {
    let state = readyState
    if state != .closed {
      // Actor deinitialization cannot reliably deliver callbacks; direct users must call close()
      // when they need close/error notification before releasing the event source.
      logger.error(
        "EventSource deinitialized while \(state.rawValue, privacy: .public); call close() before release"
      )
    }

    dataEventStreamTask?.cancel()
    queuedReconnectTask?.cancel()
    reconnectTask?.cancel()
    eventTimeoutTask?.cancel()
  }



  // MARK: Event Handlers


  /// Sets the handler to call when the connection is opened.
  ///
  /// - Note: This may be called multiple times. Each successful reconnection attempt will fire an
  ///   open event.
  ///
  public func setOnOpen(_ handler: (@Sendable () -> Void)?) {
    onOpen = handler
  }

  /// Sets the handler to call when the connection experiences an error.
  ///
  /// - Note: This may be called multiple times. Any interruption to an active connection will result
  ///   in an error event being fired, including for reconnections.
  ///
  public func setOnError(_ handler: (@Sendable (Swift.Error?) -> Void)?) {
    onError = handler
  }

  // Internal state-aware error hook used by transport-owned streams to finish on terminal errors
  // without re-entering the actor from the callback queue.
  func setOnStateError(_ handler: StateErrorHandler?) {
    onStateError = handler
  }

  /// Sets the handler to call when any new event is received.
  public func setOnMessage(_ handler: EventHandler?) {
    onMessage = handler
  }

  /// Adds a new message handler for a specific type of event.
  ///
  /// - Parameters:
  ///   - event: Type of event to register the handler for.
  ///   - handler: Handler for received messages of type `event`.
  /// - Returns: Unique id of registered handler.
  ///
  @discardableResult
  public func addEventListener(
    for event: String,
    _ handler: @escaping EventHandler
  ) -> UUID {
    let id = UUID()
    var handlers = eventListeners[event] ?? [:]
    handlers[id] = handler
    eventListeners[event] = handlers
    return id
  }

  /// Removes a message handler for a specific type of event.
  ///
  /// - Parameters:
  ///   - handlerId: Id of handler returned from `addEventListener`.
  ///   - event: Type of event the handler was registered for.
  ///
  public func removeEventListener(handlerId: UUID, for event: String) {
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

  /// List of unique event types that handlers are registered for.
  public func registeredListenerTypes() -> [String] {
    Array(eventListeners.keys)
  }



  // MARK: Connect


  /// Opens a connection to the server.
  ///
  /// If the connection is already `open` or `connecting`, this does nothing.
  ///
  public func connect() {
    guard readyState == .closed else {
      return
    }

    readyState = .connecting
    internalConnect()
  }

  func connect(unless shouldCancel: @Sendable () -> Bool) {
    guard !shouldCancel() else {
      return
    }

    connect()
  }

  private func internalConnect() {

    guard readyState != .closed else {
      #if EVENT_SOURCE_EXTRA_LOGGING
      logger.debug("Skipping connect due to close")
      #endif
      return
    }

    logger.debug("Connecting")

    eventParser.reset()

    connectionAttemptTime = .now()

    let headers = connectionHeaders()
    let dataEventStreamFactory = self.dataEventStreamFactory

    dataEventStreamTask?.cancel()
    dataEventStreamTask = Task { [weak self] in
      await Self.runConnection(
        eventSource: self,
        headers: headers,
        dataEventStreamFactory: dataEventStreamFactory
      )
    }
  }

  private func connectionHeaders() -> HTTP.Headers {
    var headers = HTTP.Headers()
    headers[HTTP.StdHeaders.accept] = [MediaType.eventStream.value]

    if let lastEventId {
      headers[HTTP.StdHeaders.lastEventId] = [lastEventId]
    }

    return headers
  }

  private nonisolated static func runConnection(
    eventSource: EventSource?,
    headers: HTTP.Headers,
    dataEventStreamFactory: @Sendable (HTTP.Headers) async throws -> URLSession.DataEventStream?
  ) async {
    do {
      try await processConnection(
        eventSource: eventSource,
        headers: headers,
        dataEventStreamFactory: dataEventStreamFactory
      )
    }
    catch {
      guard !Task.isCancelled else {
        return
      }

      await eventSource?.receivedError(error: error)
    }
  }

  private nonisolated static func processConnection(
    eventSource: EventSource?,
    headers: HTTP.Headers,
    dataEventStreamFactory: @Sendable (HTTP.Headers) async throws -> URLSession.DataEventStream?
  ) async throws {
    guard !Task.isCancelled else {
      return
    }

    guard let dataStream = try await dataEventStreamFactory(headers) else {
      logger.debug("Stream factory empty")
      await eventSource?.close(notifying: Error.requestStreamEmpty)
      return
    }

    var dataEventIterator = dataStream.makeAsyncIterator()
    while !Task.isCancelled {
      guard await eventSource?.isConnectionTaskActive() == true else {
        return
      }

      guard let event = try await dataEventIterator.next() else {
        break
      }

      switch event {
      case .connect:
        guard await eventSource?.receivedHeaders() == true else {
          return
        }

      case .data(let data):
        guard await eventSource?.receivedData(data) == true else {
          return
        }
      }
    }

    guard !Task.isCancelled else {
      return
    }

    await eventSource?.receivedComplete()
  }

  private func isConnectionTaskActive() -> Bool {
    readyState != .closed
  }



  // MARK: Close


  /// Closes any current connection to the server.
  ///
  /// If the connection is not `open` or `connecting`, this does nothing.
  ///
  public func close() {
    close(notifying: nil)
  }

  private func close(notifying error: Swift.Error?) {
    logger.debug("Closed")

    guard readyState != .closed else {
      return
    }

    readyState = .closed

    fireErrorEvent(error: error)

    internalClose(cancelConnection: true)
  }

  private func internalClose(cancelConnection: Bool) {

    if cancelConnection {
      dataEventStreamTask?.cancel()
    }
    dataEventStreamTask = nil

    cancelReconnect()

    stopEventTimeoutCheck()
  }



  // MARK: Event Timeout


  private func startEventTimeoutCheck(lastEventReceivedTime: DispatchTime) {

    stopEventTimeoutCheck()

    guard eventTimeoutInterval != nil else {
      return
    }

    self.lastEventReceivedTime = lastEventReceivedTime

    let eventTimeoutCheckInterval = self.eventTimeoutCheckInterval
    eventTimeoutTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: eventTimeoutCheckInterval.duration)
        }
        catch {
          return
        }

        guard !Task.isCancelled else {
          return
        }

        guard let self else {
          return
        }

        await self.checkEventTimeout()
      }
    }
  }

  private func stopEventTimeoutCheck() {
    eventTimeoutTask?.cancel()
    eventTimeoutTask = nil
  }

  private func checkEventTimeout() {

    guard let eventTimeoutInterval else {
      stopEventTimeoutCheck()
      return
    }

    #if EVENT_SOURCE_EXTRA_LOGGING
    logger.debug("Checking Event Timeout")
    #endif

    let eventTimeoutDeadline = lastEventReceivedTime + eventTimeoutInterval

    guard DispatchTime.now() >= eventTimeoutDeadline else {
      return
    }

    logger.debug("Event Timeout Deadline Expired")

    stopEventTimeoutCheck()

    fireErrorEvent(error: Error.eventTimeout)

    scheduleReconnectAfterQueuedCallbacks(cancelConnection: true)
  }



  // MARK: Connection Handlers


  private func receivedHeaders() -> Bool {

    guard readyState == .connecting else {
      logger.error("Invalid state for receiving headers: state=\(self.readyState.rawValue, privacy: .public)")

      fireErrorEvent(error: Error.invalidState)

      scheduleReconnectAfterQueuedCallbacks(cancelConnection: true)
      return false
    }

    readyState = .open

    logger.debug("Opened")

    retryAttempt = 0

    startEventTimeoutCheck(lastEventReceivedTime: .now())

    if let onOpen {
      callbackQueue.async {
        onOpen()
      }
    }

    return true
  }

  private func receivedData(_ data: Data) -> Bool {

    guard readyState == .open else {
      logger.error("Invalid state for receiving data: state=\(self.readyState.rawValue, privacy: .public)")

      fireErrorEvent(error: Error.invalidState)

      scheduleReconnectAfterQueuedCallbacks(cancelConnection: true)
      return false
    }

    logger.debug("Received Data: count=\(data.count)")

    eventParser.process(data: data, dispatcher: dispatchParsedEvent)

    return true
  }

  private func receivedError(error: Swift.Error) {

    if readyState == .closed {
      return
    }

    if isCancellationError(error: error) {
      close(notifying: error)
      return
    }

    logger.debug("Received Error: \(error.localizedDescription, privacy: .public)")

    fireErrorEvent(error: error)

    if readyState != .closed {
      scheduleReconnectAfterQueuedCallbacks(cancelConnection: false)
    }
  }

  private func receivedComplete() {

    if readyState == .closed {
      return
    }

    logger.debug("Received Complete")

    scheduleReconnectAfterQueuedCallbacks(cancelConnection: false)
  }

  private func isCancellationError(error: Swift.Error) -> Bool {
    switch error {
    case let urlError as URLError where urlError.code == .cancelled: return true
    case is CancellationError: return true
    default: return false
    }
  }


  // MARK: Reconnection


  private func scheduleReconnect(cancelConnection: Bool) {

    internalClose(cancelConnection: cancelConnection)

    guard readyState != .closed else {
      return
    }

    readyState = .connecting

    let lastConnectTime = connectionAttemptTime?.distance(to: .now()) ?? .microseconds(0)

    let retryDelay = Self.calculateRetryDelay(
      retryAttempt: retryAttempt,
      retryTime: retryTime,
      lastConnectTime: lastConnectTime
    )

    logger.debug("Scheduling Reconnect delay=\(retryDelay.totalSeconds, format: .fixed(precision: 3))")

    retryAttempt += 1

    reconnectTask = Task { [weak self] in
      do {
        try await Task.sleep(for: retryDelay.duration)
      }
      catch {
        return
      }

      guard !Task.isCancelled else {
        return
      }

      await self?.internalConnect()
    }
  }

  private func scheduleReconnectAfterQueuedCallbacks(cancelConnection: Bool) {
    queuedReconnectTask?.cancel()
    queuedReconnectTask = Task { [weak self, callbackQueue] in
      await withCheckedContinuation { continuation in
        callbackQueue.async {
          continuation.resume()
        }
      }

      guard !Task.isCancelled else {
        return
      }

      await self?.runQueuedReconnect(cancelConnection: cancelConnection)
    }
  }

  private func runQueuedReconnect(cancelConnection: Bool) {
    guard !Task.isCancelled else {
      return
    }

    queuedReconnectTask = nil
    scheduleReconnect(cancelConnection: cancelConnection)
  }

  private func cancelReconnect() {
    queuedReconnectTask?.cancel()
    queuedReconnectTask = nil

    reconnectTask?.cancel()
    reconnectTask = nil
  }

  static func calculateRetryDelay(
    retryAttempt: Int,
    retryTime: DispatchTimeInterval,
    lastConnectTime: DispatchTimeInterval
  ) -> DispatchTimeInterval {

    let retryMultiplier = Double(min(retryAttempt, Self.maxRetryTimeMultiplier))
    let retryTime = Double(retryTime.totalMilliseconds)

    var retryDelay = pow(retryMultiplier, retryExponent) * retryTime

    if retryAttempt > 0 {

      retryDelay -= Double(lastConnectTime.totalMilliseconds)

      retryDelay = max(retryDelay, retryTime)
    }

    return .milliseconds(Int(retryDelay))
  }



  // MARK: Event Parsing


  private func dispatchParsedEvent(_ info: EventInfo) {

    lastEventReceivedTime = .now()

    if let retry = info.retry {

      if let retryTime = Int(retry.trimmingCharacters(in: .whitespaces), radix: 10) {
        logger.debug("Update retry timeout: retryTime=\(retryTime)ms")

        self.retryTime = .milliseconds(retryTime)

      }
      else {
        logger.debug("Ignoring invalid retry timeout message: retry=\(retry, privacy: .public)")
      }

    }

    if info.event == nil, info.id == nil, info.data == nil {
      return
    }

    if let eventId = info.id {
      if !eventId.contains("\0") {

        lastEventId = eventId
      }
      else {
        logger.debug("Event id contains null, unable to use for last-event-id")
      }
    }

    let onMessage = self.onMessage
    let eventHandlers = info.event.flatMap { eventListeners[$0] }

    callbackQueue.async {
      if let onMessage {

        logger.debug(
          "Dispatch onMessage: event=\(info.event ?? "", privacy: .public), id=\(info.id ?? "", privacy: .public)"
        )

        onMessage(info.event, info.id, info.data)
      }

      if let event = info.event, let eventHandlers {

        for eventHandler in eventHandlers {

          logger.debug(
            "Dispatch listener: event=\(event, privacy: .public), id=\(info.id ?? "", privacy: .public)"
          )

          eventHandler.value(event, info.id, info.data)
        }
      }
    }

  }

  private func fireErrorEvent(error: Swift.Error?) {

    let readyState = self.readyState

    if let onError {
      callbackQueue.async { onError(error) }
    }

    if let onStateError {
      callbackQueue.async { onStateError(error, readyState) }
    }

  }

}


private struct EventSourceDefaults: Sendable {
  var retryTime = DispatchTimeInterval.milliseconds(100)
  var eventTimeoutInterval: DispatchTimeInterval? = DispatchTimeInterval.seconds(120)
  var eventTimeoutCheckInterval = DispatchTimeInterval.seconds(100)
}


private let eventSourceDefaults = Mutex(EventSourceDefaults())


public extension HTTP.StdHeaders {
  static let lastEventId = "Last-Event-Id"
}


private extension DispatchTimeInterval {

  var duration: Duration {
    .milliseconds(totalMilliseconds)
  }

}
