//
//  NetworkRequestAdapter.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


public protocol NetworkRequestAdapter {
  
  typealias AdaptResult = AnyPublisher<URLRequest, Error>

  func adapt(requestFactory: NetworkRequestFactory, urlRequest: URLRequest) -> AdaptResult

}
