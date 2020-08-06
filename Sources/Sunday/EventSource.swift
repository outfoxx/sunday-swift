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
import RxSwift


private let logger = logging.for(category: "event-source")


open class EventSource {

  public enum Error: Swift.Error {
    case invalidState
  }

  public enum State: String, CaseIterable {
    case connecting
    case open
    case closed
  }

  public fileprivate(set) var state = State.closed
  public fileprivate(set) var retryTime = 3000

  private let requestor: (HTTP.Headers) -> Observable<StreamResponseEvent>
  private var data$Disposer: Disposable?
  private var receivedString: String?
  private var onOpenCallback: (() -> Void)?
  private var onErrorCallback: ((Swift.Error?) -> Void)?
  private var onMessageCallback: ((String?, String?, String?) -> Void)?
  private var eventListeners = [String: (String?, String?, String?) -> Void]()
  private var queue: DispatchQueue
  private var receivedDataBuffer: Data
  private var lastEventId: String?

  private var event = [String: String]()


  public init(queue: DispatchQueue = .global(qos: .background), requestor: @escaping (HTTP.Headers) -> Observable<StreamResponseEvent>) {

    self.requestor = requestor
    self.queue = queue
    self.receivedString = nil
    self.receivedDataBuffer = Data()
  }

  public static func defaultSessionConfiguration() -> URLSessionConfiguration {

    let configuration = URLSessionConfiguration.default

    configuration.timeoutIntervalForRequest = TimeInterval(INT_MAX)
    configuration.timeoutIntervalForResource = TimeInterval(INT_MAX)

    return configuration
  }

  // Mark: Connect

  open func connect() {
    if state == .connecting || state == .open {
      return
    }

    state = .connecting

    var headers = HTTP.Headers()
    if let lastEventId = lastEventId {
      headers[lastEventIdHeader] = [lastEventId]
    }
    
    data$Disposer =
      requestor(headers)
        .map { event in
          switch event {
          case .connect(let response):
            try self.receivedHeaders(response)
          case .data(let data):
            try self.receivedData(data)
          }
        }
        .subscribe(
          onError: { error in
            self.receivedError(error: error)
          },
          onCompleted: {
            self.receivedComplete()
          }
        )
  }

  // Mark: Close

  open func close() {

    state = .closed

    data$Disposer?.dispose()
    data$Disposer = nil
  }

  // Mark: EventListeners

  open func onOpen(_ onOpenCallback: @escaping () -> Void) {

    self.onOpenCallback = onOpenCallback
  }

  open func onError(_ onErrorCallback: @escaping (Swift.Error?) -> Void) {

    self.onErrorCallback = onErrorCallback
  }

  open func onMessage(_ onMessageCallback: @escaping (_ id: String?, _ event: String?, _ data: String?) -> Void) {
    self.onMessageCallback = onMessageCallback
  }

  open func addEventListener(_ event: String, handler: @escaping (_ id: String?, _ event: String?, _ data: String?) -> Void) {
    eventListeners[event] = handler
  }

  open func removeEventListener(_ event: String) {
    eventListeners.removeValue(forKey: event)
  }

  open func events() -> [String] {
    return Array(eventListeners.keys)
  }

  // MARK: Handlers

  fileprivate func receivedHeaders(_ response: HTTPURLResponse) throws {
    guard state == .connecting else {
      close()
      throw Error.invalidState
    }

    state = .open

    logger.debug("Opened")

    onOpenCallback.flatMap { queue.async(execute: $0) }
  }

  fileprivate func receivedData(_ data: Data) throws {
    guard state == .open else {
      close()
      throw Error.invalidState
    }

    guard !data.isEmpty else {
      return
    }

    logger.debug("Received data, count=\(data.count)")

    receivedDataBuffer.append(data)

    let eventStrings = extractEventStringsFromBuffer()
    parseEventStrings(eventStrings)
  }

  fileprivate func receivedError(error: Swift.Error) {

    guard (error as? URLError)?.code != .cancelled else {
      return
    }

    logger.debug("Error: \(error)")

    scheduleReconnect()

    if let onErrorCallback = onErrorCallback {
        queue.async { onErrorCallback(error) }
    }
  }

  fileprivate func receivedComplete() {
    
    if state != .closed {
      
      scheduleReconnect()
      
      return
    }

    logger.debug("Closed")

    return
  }

  // MARK: Helpers
  
  fileprivate func scheduleReconnect() {

    let nanoseconds = Double(retryTime) / 1000.0 * Double(NSEC_PER_SEC)
    let delayTime = DispatchTime.now() + Double(Int64(nanoseconds)) / Double(NSEC_PER_SEC)

    queue.asyncAfter(deadline: delayTime, execute: connect)
  }

  fileprivate func extractEventStringsFromBuffer() -> [String] {

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

  fileprivate func searchForSeparatorInRange(_ searchRange: Range<Int>) -> Range<Int>? {

    for delimiter in validSeparatorSequences {

      if let foundRange = receivedDataBuffer.range(of: delimiter, options: [], in: searchRange) {
        return foundRange
      }

    }

    return nil
  }

  fileprivate func parseEventStrings(_ eventStrings: [String]) {

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
        
        self.retryTime = Int(retry.trimmingCharacters(in: .whitespaces)) ?? self.retryTime
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

  fileprivate func parseEvent(_ eventString: String) -> (id: String?, event: String?, data: String?, retry: String?) {

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


public class ObservableEventSource<D: Decodable>: EventSource {


  private let eventDecoder: MediaTypeDecoder


  public init(eventDecoder: MediaTypeDecoder, queue: DispatchQueue, requestor: @escaping (HTTP.Headers) -> Observable<StreamResponseEvent>) {
    self.eventDecoder = eventDecoder
    super.init(queue: queue, requestor: requestor)
  }

  public func observe() -> Observable<D> {
    return Observable.create { observer -> Disposable in

      // Add handler for all events

      self.onMessage { _, event, data in

        // Convert "data" value to JSON
        guard let data = #"{"type": "\#(event ?? "")", "value": \#(data ?? "nil") }"#.data(using: .utf8) else {
          logger.error("Unable to parse event data")
          return
        }

        // Parse JSON and pass event on

        do {
          let event = try self.eventDecoder.decode(D.self, from: data)

          observer.on(.next(event))
        }
        catch {
          logger.error("Unable to decode event: \(error)")
          return
        }

      }

      self.connect()

      return Disposables.create {
        self.close()
      }
    }
  }

}


private let validNewlines = ["\r\n", "\n", "\r"]
private let validSeparatorSequences = validNewlines.map { "\($0)\($0)".data(using: .utf8)! }

private let lastEventIdHeader = "Last-Event-Id"
