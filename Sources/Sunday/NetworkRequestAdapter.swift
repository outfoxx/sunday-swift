//
//  NetworkRequestAdapter.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Combine
import Foundation


public protocol NetworkRequestAdapter {

  typealias AdaptResult = AnyPublisher<URLRequest, Error>

  func adapt(requestFactory: NetworkRequestFactory, urlRequest: URLRequest) -> AdaptResult

}
