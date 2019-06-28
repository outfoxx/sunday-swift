//
//  Empty.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/18/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation


public struct Empty {

  public static let instance = Empty()

  public static let none : Empty? = nil

}

extension Empty : Decodable {}
extension Empty : Encodable {}


let emptyDataStatusCodes: Set<Int> = [204, 205]
