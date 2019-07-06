//
//  HTTPURLResponseExts.swift
//  
//
//  Created by Kevin Wooten on 7/6/19.
//

import Foundation


public extension HTTPURLResponse {

  /**
   Returns the value which corresponds to the given header
   field. Note that, in keeping with the HTTP RFC, HTTP header field
   names are case-insensitive.

   - Attention: This backports an equivalent method introduced in `macOS 10.15`, `iOS 13`, `tvOS 13`, and `watchOS 6` and
   is obsoleted beginning with those versions to use the platform provided method.

   - Parameters:
     - field: The header field name to use for the lookup (case-insensitive).
   - Returns: The value associated with the given header field, or nil if there  is no value associated with the given header field.
   */

  @available(macOS, introduced: 10.12, obsoleted: 10.15)
  @available(iOS, introduced: 10, obsoleted: 13)
  @available(tvOS, introduced: 10, obsoleted: 13)
  @available(watchOS, introduced: 3, obsoleted: 6)

  func value(forHTTPHeaderField field: String) -> String? {
    return allHeaderFields.first { $0.key.description.lowercased() == field.lowercased() }.map { String(describing: $0.value) }
  }

}
