//
//  RoutableResponseEncoding.swift
//  
//
//  Created by Kevin Wooten on 7/5/19.
//

import Foundation
import Sunday


/// Encodes response values using an encoder selected via the provided `scheme`.
///
public struct ResponseEncoding : Routable {

  /// Scheme use to encode response values
  ///
  public enum Scheme {

    /// Encodes values using a negotiated media type and
    /// updates the `Content-Type` header accordingly.
    ///
    /// The content-type is negotiated by matching
    /// the available `MediaTypeEncoder`s with the types provided
    /// in the request's `Accept` header.  If no accept header is present
    /// the type provided in `default` will be used. If negotiation fails a
    /// standard `406 NOT ACCEPTABLE` is returned.
    ///
    case negotiated(default: MediaType? = nil)

    /// Encodes values as the given media type.
    ///
    /// A `MediaTypeEncoder` must be available, if one is not
    /// available a standard `406 NOT ACCEPTABLE` is returned.
    ///
    case always(MediaType)

    public static var negotiated: Scheme { return .negotiated() }

  }

  public let scheme: Scheme
  public let encoders: MediaTypeEncoders
  public let routable: Routable

  public init(scheme: Scheme = .negotiated(default: nil), encoders: MediaTypeEncoders = .default, @RoutableBuilder buildRoutable: () -> Routable) {
    self.scheme = scheme
    self.encoders = encoders
    self.routable = buildRoutable()
  }

  public func route(_ route: Route, request: HTTPRequest) throws -> RouteResult? {
    // Attempt request routing and check for handled response
    guard let routed = try routable.route(route, request: request) else {
      return nil
    }

    // Determine the acceptable response types using the scheme
    let acceptableTypes: [MediaType]
    switch self.scheme {
    case .negotiated(let defaultType):
      let defaultTypes = defaultType != nil ? [defaultType!] : []
      acceptableTypes = (MediaType.from(accept: request.headers[HTTP.StdHeaders.accept] ?? [])) + defaultTypes

    case .always(let defaultType):
      acceptableTypes = [defaultType]
    }

    // Negotiate the response's content type and associated encoder, if negotiation fails the routing
    // is passed on; allowing any encoders further up in the stream to attempt to encode the value.
    guard let (contentType, _) = negotiate(acceptableTypes: acceptableTypes) else {
      return routed
    }

    let handler: RouteHandler = { route, request, response in

      // Update/replace content-type header
      response.setContentType(contentType)

      try routed.handler(route, request, EncodingHTTPResponse(response: response, encoders: self.encoders))

    }

    return (routed.route, handler)
  }

  private func negotiate(acceptableTypes: [MediaType]) -> (MediaType, MediaTypeEncoder)? {

    for acceptableType in acceptableTypes {
      if let encoder = try? encoders.find(for: acceptableType) {
        return (acceptableType, encoder)
      }
    }

    return nil
  }

}


class EncodingHTTPResponse: HTTPResponse {

  let response: HTTPResponse
  let encoders: MediaTypeEncoders

  init(response: HTTPResponse, encoders: MediaTypeEncoders) {
    self.response = response
    self.encoders = encoders
  }

  var server: HTTPServer { response.server }

  var state: HTTPResponseState { response.state }

  var properties: [String : Any] {
    get { return response.properties }
    set { response.properties = newValue }
  }

  func headers(forName name: String) -> [String] {
    return response.headers(forName: name)
  }

  func setHeaders(_ values: [String], forName name: String) {
    return response.setHeaders(values, forName: name)
  }

  func setContentType(_ contentType: MediaType) {
    return response.setContentType(contentType)
  }

  func start(status: HTTP.Response.Status, headers: [String : [String]]) {
    response.start(status: status, headers: headers)
  }

  func send(body: Data) {
    response.send(body: body)
  }

  func send(chunk: Data) {
    response.send(chunk: chunk)
  }

  func finish(headers: HTTP.Headers) {
    return response.finish(headers: headers)
  }

  func send<V>(status: HTTP.Response.Status, headers: [String : [String]], value: V) where V : Encodable {
    guard let contentType = MediaType(response.header(forName: HTTP.StdHeaders.contentType) ?? "") else {
      return send(status: .notAcceptable, text: "Response Content-Type Not Present")
    }

    do {

      let encoder = try encoders.find(for: contentType)

      let data = try encoder.encode(value)

      var headers = headers
      headers[HTTP.StdHeaders.contentLength] = [data.count.description]

      start(status: status, headers: headers)
      send(body: data)
      
    }
    catch {
      return send(status: .internalServerError, text: "Response Encoding Failed: \(error)")
    }
  }

}
