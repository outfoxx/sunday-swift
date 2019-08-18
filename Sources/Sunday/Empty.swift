//
//  Empty.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public struct Empty {

  public static let instance = Empty()

  public static let none: Empty? = nil

}

extension Empty: Decodable {}
extension Empty: Encodable {}


let emptyDataStatusCodes: Set<Int> = [204, 205]
