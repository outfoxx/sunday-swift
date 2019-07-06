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

  public func route(request: HTTP.Request, path: String, variables: [String : Any]) throws -> HTTP.Response? {
    // Attempt request routing and check for handled response
    guard let response = try routable.route(request: request, path: path, variables: variables) else {
      return nil
    }

    // Skip handling anything that isn't a value entity response
    guard case .value(let generator) = response.entity else {
      return response
    }

    // Determine the acceptable response types using the scheme
    let acceptableTypes: [MediaType]
    switch scheme {
    case .negotiated(let defaultType):
      let defaultTypes = defaultType != nil ? [defaultType!] : []
      acceptableTypes = (MediaType.from(accept: request.headers[HTTP.StdHeaders.accept] ?? [])) + defaultTypes

    case .always(let defaultType):
      acceptableTypes = [defaultType]
    }

    // Negotiate the response's content type and associated encoder, if negotiation fails the response
    // is passed on; allowing any encoders further up in the stream to attempt to encode the value.
    guard let (contentType, encoder) = negotiate(request: request, acceptableTypes: acceptableTypes) else {
      return response
    }

    // Update/replace content-type header
    var headers = response.headers
    headers[HTTP.StdHeaders.contentType] = [contentType.value]

    do {
      // Encode the value and return a new response

      let data = try generator(encoder)

      return HTTP.Response(status: response.status,
                           headers: headers,
                           entity: .data(data))
    }
    catch {
      // Encoding failed, report it in HTTP response

      let responseData = "Value Encoding Failed: \(error)".data(using: .utf8) ?? Data()
      headers[HTTP.StdHeaders.contentType] = [MediaType.plain.value]
      return HTTP.Response(status: .internalServerError, headers: headers, entity: .data(responseData))
    }
  }

  private func negotiate(request: HTTP.Request, acceptableTypes: [MediaType]) -> (MediaType, MediaTypeEncoder)? {

    for acceptableType in acceptableTypes {
      if let encoder = try? encoders.find(for: acceptableType) {
        return (acceptableType, encoder)
      }
    }

    return nil
  }

}
