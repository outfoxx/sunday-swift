//
//  EndpointManager.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public protocol EndpointManager {

  var requestManager: RequestManager { get }

  init(requestManager: RequestManager)

}
