//
//  EventSource.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Alamofire
import Foundation
import RxSwift


private let validNewlines = ["\r\n", "\n", "\r"]
private let validNewlineSequences = validNewlines.map { "\($0)\($0)".data(using: .utf8)! }

private let logger = logging.for(category: "event-source")


open class EventSource {

  public enum State: String, CaseIterable {
    case connecting
    case open
    case closed
  }

  public typealias RequestFactory = () throws -> DataRequest

  public fileprivate(set) var readyState = State.closed
  public fileprivate(set) var retryTime = 3000

  private let requestFactory: RequestFactory
  private var request: Request?
  private var receivedString: String?
  private var onOpenCallback: (() -> Void)?
  private var onErrorCallback: ((Error?) -> Void)?
  private var onMessageCallback: ((String?, String?, String?) -> Void)?
  private var eventListeners = [String: (String?, String?, String?) -> Void]()
  private var queue: DispatchQueue
  private var errorBeforeSetErrorCallBack: Error?
  private var receivedDataBuffer: Data
  private var lastEventId: String?

  private var event = [String: String]()


  public init(queue: DispatchQueue = DispatchQueue.global(qos: .background), requestFactory: @escaping RequestFactory) {

    self.requestFactory = requestFactory
    self.queue = queue
    receivedString = nil
    receivedDataBuffer = Data()

    readyState = .closed
  }

  public static func defaultSessionConfiguration() -> URLSessionConfiguration {

    let configuration = URLSessionConfiguration.default

    configuration.timeoutIntervalForRequest = TimeInterval(INT_MAX)
    configuration.timeoutIntervalForResource = TimeInterval(INT_MAX)

    return configuration
  }

  // Mark: Connect

  open func connect() {

    readyState = .connecting

    do {

      request = try requestFactory()
        .stream(closure: receivedData)
        .response(completionHandler: receivedResponse)

    }
    catch {
      logger.error("Error creating event source request: \(error)")
    }
  }

  // Mark: Close

  open func close() {

    readyState = .closed

    request?.cancel()
    request = nil
  }

  fileprivate func receivedMessageToClose(_ response: HTTPURLResponse?) -> Bool {

    guard let response = response else {
      return false
    }

    if response.statusCode == 204 {
      close()
      return true
    }

    return false
  }

  // Mark: EventListeners

  open func onOpen(_ onOpenCallback: @escaping () -> Void) {

    self.onOpenCallback = onOpenCallback
  }

  open func onError(_ onErrorCallback: @escaping (Error?) -> Void) {

    self.onErrorCallback = onErrorCallback

    if let errorBeforeSet = errorBeforeSetErrorCallBack {
      self.onErrorCallback!(errorBeforeSet)
      errorBeforeSetErrorCallBack = nil
    }
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

  fileprivate func receivedData(_ data: Data) {

    switch readyState {
    case .connecting:

      readyState = .open

      logger.debug("Opened")

      if let onOpenCallback = onOpenCallback {
        queue.async(execute: onOpenCallback)
      }

    case .open:

      break

    default:

      logger.debug("Ignored Data, invalid state: \(readyState)")

      return
    }

    logger.debug("Received Data")

    receivedDataBuffer.append(data)

    let eventStream = extractEventsFromBuffer()
    parseEventStream(eventStream)
  }

  fileprivate func receivedResponse(_ dataResponse: DefaultDataResponse) {

    readyState = .closed

    if receivedMessageToClose(dataResponse.response) {

      logger.debug("Closed")

      return
    }

    let error = dataResponse.error
    if error == nil || (error as? URLError)?.code != .cancelled {

      logger.debug("Closed: \(error)")

      let nanoseconds = Double(retryTime) / 1000.0 * Double(NSEC_PER_SEC)
      let delayTime = DispatchTime.now() + Double(Int64(nanoseconds)) / Double(NSEC_PER_SEC)

      queue.asyncAfter(deadline: delayTime, execute: connect)
    }

    queue.async {

      if let errorCallback = self.onErrorCallback {
        errorCallback(error)
      }
      else {
        self.errorBeforeSetErrorCallBack = error
      }

    }

  }

  // MARK: Helpers

  fileprivate func extractEventsFromBuffer() -> [String] {

    var events = [String]()

    // Find first occurrence of delimiter
    var searchRange: Range<Int> = 0 ..< receivedDataBuffer.count
    while let delimterRange = searchForDelimiterInRange(searchRange) {

      let dataRange = Range(uncheckedBounds: (searchRange.lowerBound, delimterRange.upperBound))

      let dataChunk = receivedDataBuffer.subdata(in: dataRange)

      events.append(String(data: dataChunk, encoding: .utf8)!)

      // Search for next occurrence of delimiter
      searchRange = Range(uncheckedBounds: (delimterRange.upperBound, searchRange.upperBound))
    }

    // Remove the found events from the buffer
    receivedDataBuffer.replaceSubrange(0 ..< searchRange.lowerBound, with: Data())

    return events
  }

  fileprivate func searchForDelimiterInRange(_ searchRange: Range<Int>) -> Range<Int>? {

    for delimiter in validNewlineSequences {

      if let foundRange = receivedDataBuffer.range(of: delimiter, options: [], in: searchRange) {
        return foundRange
      }

    }

    return nil
  }

  fileprivate func parseEventStream(_ events: [String]) {

    var parsedEvents: [(id: String?, event: String?, data: String?)] = Array()

    for event in events {
      if event.isEmpty {
        continue
      }

      if event.hasPrefix(":") {
        continue
      }

      if (event as String).contains("retry:") {
        if let reconnectTime = parseRetryTime(event) {
          retryTime = reconnectTime
        }
        continue
      }

      parsedEvents.append(parseEvent(event))
    }

    for parsedEvent in parsedEvents {

      lastEventId = parsedEvent.id

      if let data = parsedEvent.data, let onMessage = onMessageCallback {

        queue.async {
          onMessage(self.lastEventId, parsedEvent.event, data)
        }

      }

      if let event = parsedEvent.event, let data = parsedEvent.data, let eventHandler = eventListeners[event] {
        queue.async {
          eventHandler(self.lastEventId, event, data)
        }
      }
    }
  }

  fileprivate func parseEvent(_ eventString: String) -> (id: String?, event: String?, data: String?) {

    var id: String?
    var event: String?
    var data: String?

    for line in eventString.components(separatedBy: .newlines) {

      let (key, value) = parseLine(line)

      if let key = key {
        switch key {
        case "id":
          id = value
        case "event":
          event = value
        case "data":
          data = (data ?? "") + "\n" + (value ?? "")
        default:
          break
        }
      }
    }

    return (id, event, data)
  }

  fileprivate func parseLine(_ line: String) -> (String?, String?) {

    var key: NSString?, value: NSString?
    let scanner = Scanner(string: line)
    scanner.scanUpTo(":", into: &key)
    scanner.scanString(":", into: nil)

    for newline in validNewlines {
      if scanner.scanUpTo(newline, into: &value) {
        break
      }
    }

    return (key as String?, value as String?)
  }

  fileprivate func parseRetryTime(_ eventString: String) -> Int? {

    var reconnectTime: Int?
    let separators = CharacterSet(charactersIn: ":")
    if let milli = eventString.components(separatedBy: separators).last {
      let milliseconds = milli.trimmingCharacters(in: .whitespaces)

      if let intMiliseconds = Int(milliseconds) {
        reconnectTime = intMiliseconds
      }
    }
    return reconnectTime
  }

}


public class ObservableEventSource<D: Decodable>: EventSource {


  private let eventDecoder: MediaTypeDecoder


  public init(eventDecoder: MediaTypeDecoder, queue: DispatchQueue, requestFactory: @escaping RequestFactory) {
    self.eventDecoder = eventDecoder
    super.init(queue: queue, requestFactory: requestFactory)
  }

  public func observe() -> Observable<D> {
    return Observable.create { observer -> Disposable in

      // Add handler for all events

      self.onMessage { _, event, data in

        // Convert "data" value to JSON
        guard let data = (data ?? "{}").data(using: .utf8) else {
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
