//
//  RoutableContentNegotiation.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//
//  swiftlint:disable identifier_name

import Foundation
import Sunday


/// Utility to set `RequestDecoding` and `ResponseEncoding` as negotiated based on
/// `Content-Type` and `Accept` headers.
///
public func ContentNegotiation(
  decoders: MediaTypeDecoders = .default,
  encoders: MediaTypeEncoders = .default,
  @RoutableBuilder buildRoutable: () -> Routable
) -> Routable {
  RequestDecoding(scheme: .negotiated, decoders: decoders) {
    ResponseEncoding(scheme: .negotiated, encoders: encoders, buildRoutable: buildRoutable)
  }
}
