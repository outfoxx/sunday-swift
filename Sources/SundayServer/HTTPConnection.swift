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
import Network
import OSLog
import Sunday
import Synchronization


private let minHTTPReqeustLength = 16
private let maxHTTPChunkLength = 1024 * 128


/// HTTPConnection represents an active HTTP connection.
public final class HTTPConnection: Sendable {

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

  final class Response: HTTPResponse {

    private struct State {
      var responseState: HTTPResponseState = .initial
      var headers: HTTP.Headers
      var properties: [String: any Sendable] = [:]

      init(serverHeader: String) {
        headers = [
          HTTP.StdHeaders.server: [serverHeader],
          // we don't support keep-alive connection for now, just force it to be closed
          HTTP.StdHeaders.connection: ["close"],
        ]
      }
    }

    let server: HTTPServer
    let connection: HTTPConnection
    private let stateStorage: Mutex<State>

    var state: HTTPResponseState {
      stateStorage.withLock { $0.responseState }
    }

    var properties: [String: any Sendable] {
      get { stateStorage.withLock { $0.properties } }
      set { stateStorage.withLock { $0.properties = newValue } }
    }

    init(server: HTTPServer, connection: HTTPConnection) {
      self.server = server
      self.connection = connection
      stateStorage =
        Mutex(
          State(
            serverHeader:
              "SundayServer \(Bundle(for: HTTPConnection.self).infoDictionary?["CFBundleVersion"] as? String ?? "0.0")"
          )
        )
    }

    func headers(forName name: String) -> [String] {
      return stateStorage.withLock { $0.headers[name] ?? [] }
    }

    func setHeaders(_ values: [String], forName name: String) {
      stateStorage.withLock { $0.headers[name] = values }
    }

    func start(status: HTTP.Response.Status, headers: [String: [String]]) {
      let responseHeader =
        stateStorage.withLock { state in
          precondition(state.responseState == .initial)

          var headers = headers.merging(state.headers) { first, _ in first }

          if headers[HTTP.StdHeaders.transferEncoding]?.first == "chunked" {
            state.responseState = .sendingChunks
          }
          else if headers[HTTP.StdHeaders.contentLength] != nil {
            // Message body length determined by Content-Length
            state.responseState = .sendingBody
          }
          else {
            // Message body length determined by closing connection
            state.responseState = .sendingBody
            headers[HTTP.StdHeaders.connection] = ["close"]
          }

          let responseHeaderParts = [
            "HTTP/1.1 \(status)",
            headers.map { key, values in values.map { value in "\(key): \(value)" }.joined(separator: "\r\n") }
              .joined(separator: "\r\n"),
            "\r\n",
          ]

          return responseHeaderParts.joined(separator: "\r\n")
        }

      connection.send(data: responseHeader.data(using: .nonLossyASCII)!, context: "sending response header")
    }

    func send(body: Data) {
      send(body: body, final: true)
    }

    func send(body: Data, final: Bool = true) {
      stateStorage.withLock { state in
        precondition(state.responseState == .sendingBody)
        if final {
          state.responseState = .complete
        }
      }

      connection.send(data: body, context: "sending body data") { error in
        if final, error != nil || self.header(forName: HTTP.StdHeaders.connection) == "close" {
          self.connection.close()
        }
      }
    }

    func send(chunk: Data) {
      stateStorage.withLock { state in
        precondition(state.responseState == .sendingChunks)
      }

      var encodedChunk = "\(String(chunk.count, radix: 16))\r\n".data(using: .ascii)!
      encodedChunk.append(chunk)
      encodedChunk.append("\r\n".data(using: .ascii)!)
      connection.send(data: encodedChunk, context: "sending body chunk")
    }

    func finish(trailers: HTTP.Headers) {
      stateStorage.withLock { state in
        precondition(state.responseState == .sendingChunks)
      }

      send(chunk: Data())

      stateStorage.withLock { state in
        state.responseState = .complete
      }

      connection.send(data: "\r\n".data(using: .ascii)!, context: "sending final data") { [weak self] _ in
        guard let self = self else { return }
        self.connection.close()
      }
    }

  }

  let transport: NWConnection
  unowned let server: HTTPServer
  let id: String
  let logger: Logger
  let dispatcher: HTTPServer.Dispatcher
  let requestParser = Mutex(HTTPRequestParser())

  public init(
    transport: NWConnection,
    server: HTTPServer,
    id: String,
    logger: Logger,
    dispatcher: @escaping HTTPServer.Dispatcher
  ) {
    self.transport = transport
    self.server = server
    self.id = id
    self.logger = logger
    self.dispatcher = dispatcher

    self.transport.receive(
      minimumIncompleteLength: minHTTPReqeustLength,
      maximumLength: maxHTTPChunkLength,
      completion: { [weak self] content, _, isComplete, error in
        self?.handleReceive(content: content, isComplete: isComplete, error: error)
      }
    )
  }

  public func handleReceive(content: Data?, isComplete: Bool, error: Error?) {
    guard error == nil, !isComplete else {
      if let error = error {
        logger.error("network connection error: \(error.localizedDescription, privacy: .public)")
      }
      return close()
    }

    do {

      guard
        let content = content,
        let parsedRequest = try requestParser.withLock({ try $0.process(content, connection: self) })
      else {
        receive(minimum: 1, maximum: maxHTTPChunkLength) { [weak self] content, isComplete, error in
          self?.handleReceive(content: content, isComplete: isComplete, error: error)
        }
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

      let request = Request(
        server: server,
        raw: HTTP.Request(
          method: parsedRequest.line.method,
          url: parsedRequest.line.uri,
          version: parsedRequest.line.version,
          headers: headers,
          rawHeaders: parsedRequest.headers,
          body: parsedRequest.body
        ),
        parameters: [:]
      )

      let response = Response(server: server, connection: self)

      try dispatcher(request, response)
    }
    catch {
      logger.error("http processing error: \(error.localizedDescription, privacy: .public)")

    }
  }

  private func handleReceive(content: Data?, isComplete: Bool, error: NWError?) {
    handleReceive(content: content, isComplete: isComplete, error: error as Error?)
  }

  public func send(data: Data, context: String, completion: (@Sendable (Error?) -> Void)? = nil) {
    transport.send(content: data, completion: .contentProcessed { error in
      if let error = error {
        self.logger.error(
          "send error while '\(context, privacy: .public)': \(error.localizedDescription, privacy: .public)"
        )
      }
      completion?(error)
    })
  }

  public func receive(minimum: Int, maximum: Int, completion: @escaping @Sendable (Data?, Bool, Error?) -> Void) {
    transport.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { data, _, isComplete, error in
      completion(data, isComplete, error)
    }
  }

  public func close() {
    transport.cancel()
  }

}


extension HTTPConnection.Request: CustomStringConvertible {

  public var description: String {
    var lines: [String] = []

    let method = self.method.rawValue.uppercased()
    let request = url.url?.absoluteString ?? "/"
    let version = "\(raw.version.major).\(raw.version.minor)"

    lines.append("\(method) \(request) HTTP/\(version)")

    for (header, values) in headers {
      for value in values {
        lines.append("\(header.lowercased().split(separator: "-").map(\.capitalized).joined(separator: "-")): \(value)")
      }
    }

    return lines.joined(separator: "\n")
  }

}
