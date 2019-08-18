//
//  RoutableRequestDecoding.swift
//  
//
//  Created by Kevin Wooten on 7/5/19.
//

import Foundation
import Sunday


/// Decodes request bodies using a decoder selected via the provided `scheme`.
///
public struct RequestDecoding : Routable {

  /// Scheme use to decode request bodies
  ///
  public enum Scheme {

    /// Decodes a body value using a negotiated media type.
    ///
    /// The media-type is negotiated by matching
    /// the available `MediaTypeDecoder`s with the type provided
    /// in the request's `Content-Type` header.  If no content-type header
    /// is present the type provided in `default` will be used. If negotiation
    /// fails a standard `406 NOT ACCEPTABLE` is returned.
    ///
    case negotiated(default: MediaType? = nil)

    /// Decodes body values as the given media type.
    ///
    /// A `MediaTypeDecoder` must be available, if one is not
    /// available a standard `406 NOT ACCEPTABLE` is returned.
    ///
    case always(MediaType)

    public static var negotiated: Scheme { return .negotiated() }

  }

  public let scheme: Scheme
  public let decoders: MediaTypeDecoders
  public let routable: Routable

  public init(scheme: Scheme = .negotiated(default: nil), decoders: MediaTypeDecoders = .default, @RoutableBuilder buildRoutable: () -> Routable) {
    self.scheme = scheme
    self.decoders = decoders
    self.routable = buildRoutable()
  }

  public func route(_ route: Route, request: HTTPRequest) throws -> RouteResult? {
    guard let routed = try routable.route(route, request: request) else {
      return nil
    }

    let handler: RouteHandler = { route, request, response in

      if request.body != nil {

        // Determine content-type based on scheme

        let contentType: MediaType

        switch self.scheme {
        case .negotiated(let defaultType):

          // Find content-type header

          if let foundContentTypeHeaders = request.headers[HTTP.StdHeaders.contentType], let foundContentTypeHeader = foundContentTypeHeaders.first {

            // Parse content-type header

            guard let foundContentType = MediaType(foundContentTypeHeader) else {
              return response.send(status: .notAcceptable, text: "Content-Type Header Invalid")
            }

            contentType = foundContentType
          }
          else if let defaultType = defaultType {

            // Fallback to provided default

            contentType = defaultType
          }
          else {

            // Reply with negotiation error

            return response.send(status: .notAcceptable, text: "No Content-Type Header")
          }

        case .always(let defaultType):

          contentType = defaultType

        }

        response.properties["@body-decoder"] = try self.decoders.find(for: contentType)
      }

      try routed.handler(route, request, response)
    }

    return (routed.route, handler)
  }

}
