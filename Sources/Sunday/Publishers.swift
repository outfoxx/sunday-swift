//
//  Publishers.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Combine
import Foundation


public typealias RequestPublisher = AnyPublisher<URLRequest, Error>
public typealias RequestResponsePublisher = AnyPublisher<(response: HTTPURLResponse, data: Data?), Error>
public typealias RequestResultPublisher<T> = AnyPublisher<T, Error>
public typealias RequestCompletePublisher = RequestResultPublisher<Void>
public typealias RequestEventPublisher<E> = AnyPublisher<E, Error>

