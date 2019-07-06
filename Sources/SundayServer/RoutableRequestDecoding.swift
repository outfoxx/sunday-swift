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

  public func route(request: HTTP.Request, path: String, variables: [String : Any]) throws -> HTTP.Response? {

    var variables = variables

    if request.body != nil {

      // Determine content-type based on scheme

      let contentType: MediaType
      switch scheme {
      case .negotiated(let defaultType):

        // Find content-type header

        if let foundContentTypeHeaders = request.headers[HTTP.StdHeaders.contentType], let foundContentTypeHeader = foundContentTypeHeaders.first {

          // Parse content-type header

          guard let foundContentType = MediaType(foundContentTypeHeader) else {
            let data = "Content-Type Header Invalid".data(using: .utf8)!
            return HTTP.Response(status: .notAcceptable,
                                 headers: [HTTP.StdHeaders.contentType: [MediaType.plain.value]],
                                 entity: .data(data))
          }

          contentType = foundContentType
        }
        else if let defaultType = defaultType {

          // Fallback to provided default

          contentType = defaultType
        }
        else {

          // Reply with negotiation error

          let data = "No Content-Type Header".data(using: .utf8)!
          return HTTP.Response(status: .notAcceptable,
                               headers: [HTTP.StdHeaders.contentType: [MediaType.plain.value]],
                               entity: .data(data))
        }

      case .always(let defaultType):

        contentType = defaultType

      }

      variables["@body-decoder"] = try decoders.find(for: contentType)
    }

    return try routable.route(request: request, path: path, variables: variables)
  }

}
