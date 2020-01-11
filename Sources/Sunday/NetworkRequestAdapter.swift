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
import RxSwift


public protocol NetworkRequestAdapter {

  func adapt(requestManager: NetworkRequestManager, urlRequest: URLRequest) -> Single<URLRequest>

}
