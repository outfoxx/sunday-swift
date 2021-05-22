//
//  HTTPURLResponses.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public extension HTTPURLResponse {

  /**
   Returns the value which corresponds to the given header
   field. Note that, in keeping with the HTTP RFC, HTTP header field
   names are case-insensitive.

   - Attention: This backports an equivalent method introduced in `macOS 10.15`, `iOS 13`, `tvOS 13`, and `watchOS 6`.

   - Parameters:
     - field: The header field name to use for the lookup (case-insensitive).
   - Returns: The value associated with the given header field, or nil if there  is no value associated with the given header field.
   */

  func value(forHttpHeaderField field: String) -> String? {
    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
      return value(forHTTPHeaderField: field)
    }
    else {
      return allHeaderFields.first { $0.key.description.lowercased() == field.lowercased() }
        .map { String(describing: $0.value) }
    }
  }

}
