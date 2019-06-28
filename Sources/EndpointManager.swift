//
//  EndpointManager.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/12/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation


public protocol EndpointManager {

  var requestManager: RequestManager { get }

  init(requestManager: RequestManager)

}
