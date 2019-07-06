//
//  HTTPConnection.swift
//  
//
//  Created by Kevin Wooten on 6/16/19.
//

import Foundation
import Network
import Sunday
import OSLogTrace


private let minHTTPReqeustLength = 16
private let maxHTTPReqeustLength = 1024 * 500


/// HTTPConnection represents an active HTTP connection
///
@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
public final class HTTPConnection {

  enum RequestState {
    case parsingHeader
    case readingBody
  }

  enum ResponseState {
    case sendingHeader
    case sendingBody
  }

  public typealias Dispatcher = (HTTP.Request) throws -> HTTP.Response

  public weak var server: HTTPServer?
  public let id: String = UUID().uuidString
  public let transport: NWConnection
  public let dispatcher: Dispatcher
  public let log: OSLog

  private(set) var requestState: RequestState = .parsingHeader
  private(set) var responseState: ResponseState = .sendingHeader

  private var requestParser = HTTPRequestParser()

  public init(
    server: HTTPServer,
    transport: NWConnection,
    dispatcher: @escaping Dispatcher,
    log: OSLog
  ) {
    self.server = server
    self.transport = transport
    self.dispatcher = dispatcher
    self.log = log

    self.transport.receive(minimumIncompleteLength: minHTTPReqeustLength, maximumLength: maxHTTPReqeustLength, completion: handleReceive(content:context:isComplete:error:))
  }

  private func handleReceive(content: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) {
    guard error == nil, isComplete == false else {
      if let error = error {
        log.error("network connection error: \(error)")
      }
      transport.cancel()
      return
    }

    do {

      guard
        let content = content,
        let parsedRequest = try requestParser.process(content)
      else {
        transport.receive(minimumIncompleteLength: 1, maximumLength: maxHTTPReqeustLength, completion: handleReceive(content:context:isComplete:error:))
        return
      }

      // generate convenience headers as strings
      var headers: HTTP.Headers = [:]
      for header in parsedRequest.headers {
        guard let value = String(data: header.value, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) else { continue }
        var currentValues = headers[header.name] ?? []
        currentValues.append(value)
        headers.updateValue(currentValues, forKey: header.name)
      }

       let request = HTTP.Request(method: parsedRequest.line.method,
                                  url: parsedRequest.line.uri,
                                  version: parsedRequest.line.version,
                                  headers: headers,
                                  rawHeaders: parsedRequest.headers,
                                  body: content)


      do {
        let response = try dispatcher(request)
        self.send(response: response)
      }
      catch {
        self.send(error: error)
      }
    }
    catch {
      log.error("http processing error: \(error)")

    }
  }

  public func close() {
    transport.cancel()
  }

  private func send(error: Swift.Error) {
    send(response: .internalServerError(message: String(describing: error)))
  }

  private func send(response: HTTP.Response) {
    var status = response.status
    var headers = response.headers

    let sendBody: ((@escaping (Error?) -> Void) -> Void)?
    switch response.entity {
    case .data(let data):
      headers[HTTP.StdHeaders.contentLength] = ["\(data.count)"]
      sendBody = { finalizer in
        self.send(data: data, context: "sending body", completion: finalizer)
      }

    case .stream(let stream):
      headers[HTTP.StdHeaders.transferType] = ["chunked"]
      sendBody = { finalizer in
        _ = stream.subscribe(
          onNext: { data in
            self.sendChunk(data: data)
          },
          onError: { error in
            self.log.error("error streaming response entity: \(error)")
            finalizer(error)
          },
          onCompleted: {
            self.sendChunk(data: Data(), completion: finalizer)
          })
      }

    case .value:
      status = .notAcceptable
      headers[HTTP.StdHeaders.contentType] = [MediaType.plain.value]

      let data = "Content Negotiation Failed".data(using: .utf8)!
      sendBody = { finalizer in
        self.send(data: data, context: "sending error body", completion: finalizer)
      }

    case .none:
      sendBody = { finalizer in
        self.send(data: Data(), context: "sending empty body", completion: finalizer)
      }
      break
    }

    // we don't support keep-alive connection for now, just force it to be closed
    headers[HTTP.StdHeaders.connection] = ["close"]

    if headers[HTTP.StdHeaders.server]?.count == 0 {
      headers[HTTP.StdHeaders.server] = ["SundayServer \(Bundle.target.infoDictionary?["CFBundleVersion"] as? String ?? "0.0")"]
    }

    let responseHeaderParts = [
      "HTTP/1.1 \(status)",
      headers.map { (key, values) in values.map { value in "\(key): \(value)" }.joined(separator: "\r\n") }.joined(separator: "\r\n"),
      "\r\n"
    ]

    let responseHeader = responseHeaderParts.joined(separator: "\r\n").data(using: .nonLossyASCII)!
    send(data: responseHeader, context: "sending response header")

    if let sendBody = sendBody {
      sendBody { error in
        self.transport.cancel()
      }
    }
  }

  private func sendChunk(data: Data, completion: ((Error?) -> Void)? = nil) {
    var chunk = "\(String(data.count, radix: 16))\r\n".data(using: .ascii)!
    chunk.append(data)
    chunk.append("\r\n".data(using: .ascii)!)
    send(data: chunk, context: "sending body chunk", completion: completion)
  }

  private func send(data: Data, context: String, completion: ((Error?) -> Void)? = nil) {
    transport.send(content: data, completion: .contentProcessed { error in
      if let error = error {
        self.log.error("send error while '\(context)': \(error)")
      }
      completion?(error)
    })
  }

}
