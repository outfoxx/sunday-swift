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
  
  func close(cancelOutstandingRequests: Bool)

}


extension EndpointManager {
  
  public func close(cancelOutstandingRequests: Bool) {
    requestManager.close(cancelOutstandingRequests: cancelOutstandingRequests)
  }
  
}
