//
//  HTTPConnection.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Network
import OSLogTrace
import Sunday


private let minHTTPReqeustLength = 16
private let maxHTTPChunkLength = 1024 * 128


/// HTTPConnection represents an active HTTP connection
///
public class HTTPConnection {

  class Request: HTTPRequest {

    let server: HTTPServer
    let raw: HTTP.Request
    var parameters: [String: String]

    init(server: HTTPServer, raw: HTTP.Request, parameters: [String: String]) {
      self.server = server
      self.raw = raw
      self.parameters = parameters
    }

  }

  class Response: HTTPResponse {

    let server: HTTPServer
    let connection: HTTPConnection
    var state: HTTPResponseState = .initial
    var headers: HTTP.Headers = [:]
    var properties: [String: Any] = [:]

    init(server: HTTPServer, connection: HTTPConnection) {
      self.server = server
      self.connection = connection

      // Add server header
      headers[HTTP.StdHeaders.server] = ["SundayServer \(Bundle(for: HTTPConnection.self).infoDictionary?["CFBundleVersion"] as? String ?? "0.0")"]
      // we don't support keep-alive connection for now, just force it to be closed
      headers[HTTP.StdHeaders.connection] = ["close"]
    }

    func headers(forName name: String) -> [String] {
      return headers[name] ?? []
    }

    func setHeaders(_ values: [String], forName name: String) {
      headers[name] = values
    }

    func start(status: HTTP.Response.Status, headers: [String: [String]]) {
      precondition(state == .initial)

      var headers = headers.merging(self.headers) { first, _ in first }

      let nextState: HTTPResponseState
      if headers[HTTP.StdHeaders.transferType]?.first == "chunked" {
        nextState = .sendingChunks
      }
      else if headers[HTTP.StdHeaders.contentLength] != nil {
        // Message body length determined by Content-Length
        nextState = .sendingBody
      }
      else {
        // Message body length determined by closing connection
        nextState = .sendingBody
        headers[HTTP.StdHeaders.connection] = ["close"]
      }

      defer { state = nextState }

      let responseHeaderParts = [
        "HTTP/1.1 \(status)",
        headers.map { key, values in values.map { value in "\(key): \(value)" }.joined(separator: "\r\n") }.joined(separator: "\r\n"),
        "\r\n",
      ]

      let responseHeader = responseHeaderParts.joined(separator: "\r\n")
      connection.send(data: responseHeader.data(using: .nonLossyASCII)!, context: "sending response header")
    }

    func send(body: Data) {
      precondition(state == .sendingBody)
      defer { state = .complete }

      connection.send(data: body, context: "sending body data") { error in
        if error != nil || self.header(forName: HTTP.StdHeaders.connection) == "close" {
          self.connection.close()
        }
      }
    }

    func send(chunk: Data) {
      precondition(state == .sendingChunks)

      var chunk = "\(String(chunk.count, radix: 16))\r\n".data(using: .ascii)!
      chunk.append(chunk)
      chunk.append("\r\n".data(using: .ascii)!)
      connection.send(data: chunk, context: "sending body chunk")
    }

    func finish(headers: HTTP.Headers) {
      precondition(state == .sendingChunks)

      connection.send(data: "\r\n".data(using: .ascii)!, context: "sending final data") { [weak self] _ in
        guard let self = self else { return }
        self.connection.close()
      }
    }

  }

  weak var server: HTTPServer?
  let id: String
  let log: OSLog
  let dispatcher: HTTPServer.Dispatcher
  var requestParser = HTTPRequestParser()

  public init(server: HTTPServer, id: String, log: OSLog, dispatcher: @escaping HTTPServer.Dispatcher) {
    self.server = server
    self.id = id
    self.log = log
    self.dispatcher = dispatcher
  }

  public func handleReceive(content: Data?, isComplete: Bool, error: Error?) {
    guard let server = server, error == nil, isComplete == false else {
      if let error = error {
        log.error("network connection error: \(error)")
      }
      return close()
    }

    do {

      guard
        let content = content,
        let parsedRequest = try requestParser.process(content)
      else {
        receive(minimum: 1, maximum: maxHTTPChunkLength, completion: handleReceive(content:isComplete:error:))
        return
      }

      // generate convenience headers as strings
      var headers: HTTP.Headers = [:]
      for header in parsedRequest.headers {
        guard let value = String(data: header.value, encoding: .ascii) else { continue }
        var currentValues = headers[header.name] ?? []
        currentValues.append(value)
        headers.updateValue(currentValues, forKey: header.name)
      }

      let request = Request(server: server,
                            raw: HTTP.Request(method: parsedRequest.line.method,
                                              url: parsedRequest.line.uri,
                                              version: parsedRequest.line.version,
                                              headers: headers,
                                              rawHeaders: parsedRequest.headers,
                                              body: parsedRequest.body),
                            parameters: [:])

      let response = Response(server: server, connection: self)

      try dispatcher(request, response)
    }
    catch {
      log.error("http processing error: \(error)")

    }
  }

  open func send(data: Data, context: String, completion: @escaping (Error?) -> Void = { _ in }) {
    fatalError("Not Implemented")
  }

  open func receive(minimum: Int, maximum: Int, completion: @escaping (Data?, Bool, Error?) -> Void) {
    fatalError("Not Implemented")
  }

  open func close() {
    fatalError("Not Implemented")
  }

}


@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
public final class NetworkHTTPConnection: HTTPConnection {

  let transport: NWConnection

  public init(transport: NWConnection, server: HTTPServer,
              id: String, log: OSLog, dispatcher: @escaping HTTPServer.Dispatcher) {
    self.transport = transport
    super.init(server: server, id: id, log: log, dispatcher: dispatcher)

    self.transport.receive(minimumIncompleteLength: minHTTPReqeustLength, maximumLength: maxHTTPChunkLength,
                           completion: handleReceive(content:context:isComplete:error:))
  }

  private func handleReceive(content: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) {
    super.handleReceive(content: content, isComplete: isComplete, error: error)
  }

  public override func send(data: Data, context: String, completion: ((Error?) -> Void)? = nil) {
    transport.send(content: data, completion: .contentProcessed { error in
      if let error = error {
        self.log.error("send error while '\(context)': \(error)")
      }
      completion?(error)
    })
  }

  public override func receive(minimum: Int, maximum: Int, completion: @escaping (Data?, Bool, Error?) -> Void) {
    transport.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { data, _, isComplete, error in
      completion(data, isComplete, error)
    }
  }

  public override func close() {
    transport.cancel()
  }

}


extension HTTPConnection.Request: CustomStringConvertible {

  public var description: String {
    var lines: [String] = []
    lines.append("\(method.rawValue.uppercased()) \(url.url?.absoluteString ?? "/") HTTP/\(raw.version.major).\(raw.version.minor)")
    for (header, values) in headers {
      for value in values {
        lines.append("\(header.lowercased().split(separator: "-").map { $0.capitalized }.joined(separator: "-")): \(value)")
      }
    }
    return lines.joined(separator: "\n")
  }

}
