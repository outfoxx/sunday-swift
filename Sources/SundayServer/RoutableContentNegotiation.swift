//
//  RoutableContentNegotiation.swift
//  
//
//  Created by Kevin Wooten on 7/5/19.
//

import Foundation
import Sunday


/// Utility to setu `RequestDecoding` and `ResponseEncoding` as negotiated based on `Content-Type` and `Accept` headers.
///
public func ContentNegotiation(decoders: MediaTypeDecoders = .default, encoders: MediaTypeEncoders = .default, @RoutableBuilder buildRoutable: () -> Routable) -> Routable {
  RequestDecoding(scheme: .negotiated, decoders: decoders) {
    ResponseEncoding(scheme: .negotiated, encoders: encoders, buildRoutable: buildRoutable)
  }
}
