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

//  swiftlint:disable cyclomatic_complexity function_body_length

import Foundation
import Sunday


public extension HTTP {

  struct RequestLine {
    let method: HTTP.Method
    let uri: URL
    let version: HTTP.Version
  }

  enum TransferEncoding: String {
    case identity
    case chunked
  }

}

/// Parser for HTTP requests
public struct HTTPRequestParser {

  public enum Error: Swift.Error {
    case invalidRequestLineData
    case invalidHeaderData
    case invalidContentLength
    case invalidChunkFormat
  }

  public struct ParsedRequest {
    let line: HTTP.RequestLine
    let headers: HTTP.RawHeaders
    let body: Data?
  }

  enum State {
    case line
    case headers
    case body
  }

  private static let newlineData = Data([0xD, 0xA])
  private static let headerSeparator = Character(":").asciiValue!

  private var state = State.line
  private var buffer = Data()

  private var line: HTTP.RequestLine?
  private var headers: HTTP.RawHeaders?
  private var body: (HTTP.TransferEncoding, Int?)?
  private var entity: Data?

  /// Process available segment of header data
  ///  - Parameter data: the data to process
  ///  - Returns: parsed headers elements
  mutating func process(_ data: Data, connection: HTTPConnection) throws -> ParsedRequest? {

    func finish() throws -> ParsedRequest? {
      precondition(line != nil, "HTTP must have a request line")
      defer { state = .line; line = nil; headers = nil; body = nil; entity = nil }
      return ParsedRequest(line: line!, headers: headers ?? [], body: entity)
    }

    func popBytes(count: Int) -> Data {
      let bytes = buffer[0 ..< count]
      buffer = Data(buffer.suffix(from: count))
      return bytes
    }

    func peekLineBytes() -> (Data, Data.Index)? {
      // locate newline in buffer
      guard let foundNewline = buffer.range(of: Self.newlineData) else {
        return nil
      }
      return (buffer[0 ..< foundNewline.lowerBound], foundNewline.upperBound)
    }

    func popLineBytes() -> Data? {
      // locate newline in buffer
      guard let (lineBytes, lineEnd) = peekLineBytes() else {
        return nil
      }
      buffer = Data(buffer.suffix(from: lineEnd))
      return lineBytes
    }

    func pushHeader(name: String, value: Data) {
      if headers == nil {
        headers = []
      }
      headers?.append((name: name, value: value))
    }

    // Add to "current" data, will include data that couldn't be processed
    // in previous calls
    buffer.append(data)

    while buffer.count > 0 {
      switch state {
      case .line:
        guard let lineBytes = popLineBytes() else {
          // no newline so return and wait for more data
          return nil
        }

        // Ignore newlines preceeding request line
        guard !lineBytes.isEmpty else { continue }

        guard
          let lineString = String(data: lineBytes, encoding: .ascii),
          let line = parseRequestLine(from: lineString)
        else {
          throw Error.invalidRequestLineData
        }

        self.line = line
        state = .headers

      case .headers:
        guard let lineBytes = popLineBytes() else {
          // no newline so return and wait for more data
          return nil
        }

        // detect end of request headers (chunked transfers may contribute more via trailer)
        if lineBytes.isEmpty {
          // determine body type or finish with no body data
          guard let headers = headers, let body = detectRequestBodyType(headers: headers) else {
            return try finish()
          }

          if headers.contains(where: {
            $0.name.lowercased() == HTTP.StdHeaders.expect && $0.value == "100-continue".data(using: .ascii)!
          }) {

            connection.send(
              data: "HTTP/1.1 \(HTTP.Response.Status.continue)\r\n\r\n".data(using: .utf8)!,
              context: "Sending continuation for expectation"
            )
          }

          // switch to body parsing mode
          self.headers = headers
          self.body = body
          state = .body
        }
        else {

          // parse raw header
          let parts: [Data] = lineBytes.split(separator: Self.headerSeparator, maxSplits: 1)
          guard parts.count == 2, let name = String(data: parts[0], encoding: .ascii)?.lowercased() else {
            throw Error.invalidHeaderData
          }

          let value = Data(parts[1].drop { $0 == Character(" ").asciiValue })

          pushHeader(name: name, value: value)
        }

      case .body:
        guard let (type, length) = body else {
          fatalError("body state without body definition")
        }

        switch type {
        case .identity:
          guard let length = length else {
            fatalError("identity body without length")
          }

          // ensure all data for body is available, otherwise wait for more
          if length > buffer.count {
            return nil
          }

          entity = popBytes(count: length)

          return try finish()

        case .chunked:
          // Need the length line.. note that we're only "peek"ing at it
          guard let (lengthLineBytes, lengthLineEnd) = peekLineBytes() else {
            return nil
          }

          guard let lengthStr = String(data: lengthLineBytes, encoding: .ascii),
                let length = Int(lengthStr, radix: 16)
          else {
            throw Error.invalidChunkFormat
          }

          // ensure entire encoded chunk is available
          if (lengthLineEnd + length + Self.newlineData.count) > data.count {
            return nil
          }

          // remove length line from data buffer
          buffer = Data(buffer.suffix(from: lengthLineEnd))

          let chunkData = popBytes(count: length)

          // chunks are terminated with a newline, it should be left in the buffer... pop it and verify
          guard let terminator = popLineBytes(), terminator.count == 0 else {
            throw Error.invalidChunkFormat
          }

          if chunkData.count == 0 {
            // all chunks are here

            // add content length
            pushHeader(name: HTTP.StdHeaders.contentLength, value: String(entity?.count ?? 0).data(using: .ascii)!)

            // parse trailing headers (if any)
            state = .headers

          }
          else {

            // save chunk data and wait for next
            if entity == nil {
              entity = chunkData
            }
            else {
              entity!.append(chunkData)
            }
          }

        }

      }
    }

    return nil
  }
}

private func detectRequestBodyType(headers: HTTP.RawHeaders) -> (HTTP.TransferEncoding, Int?)? {
  let transferEncoding = headers.first { $0.name == HTTP.StdHeaders.transferEncoding }
    .flatMap { String(data: $0.value, encoding: .utf8) }
    .flatMap { HTTP.TransferEncoding(rawValue: $0) }
  let contentLength = headers.first { $0.name == HTTP.StdHeaders.contentLength }
    .flatMap { String(data: $0.value, encoding: .utf8) }
    .flatMap { UInt($0) }

  if transferEncoding == .chunked {
    return (.chunked, nil)
  }
  else if let contentLength = contentLength, contentLength != 0 {
    return (.identity, Int(contentLength))
  }
  return nil
}

private func parseRequestLine(from line: String) -> HTTP.RequestLine? {
  let parts = line.split(separator: " ", omittingEmptySubsequences: true)
  guard
    parts.count == 3,
    let method = HTTP.Method(rawValue: String(parts[0])),
    let uri = parseRequestURI(from: String(parts[1])),
    let version = parseHTTPVersion(from: String(parts[2]))
  else {
    return nil
  }

  return HTTP.RequestLine(method: method, uri: uri, version: version)
}

private func parseRequestURI(from uri: String) -> URL? {

  if uri == "*" {
    var comps = URLComponents()
    comps.path = uri
    return comps.url
  }

  return URL(string: uri)
}

private func parseHTTPVersion(from str: String) -> HTTP.Version? {
  guard str.hasPrefix("HTTP/") else { return nil }
  let ver = str.dropFirst(5).split(separator: ".")
  guard ver.count == 2, let major = Int(ver[0]), let minor = Int(ver[1]) else { return nil }
  return (major, minor)
}
