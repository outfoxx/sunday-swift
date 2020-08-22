//
//  Publishers.swift
//  
//
//  Created by Kevin Wooten on 8/21/20.
//

import Foundation
import Combine


public typealias RequestPublisher = AnyPublisher<URLRequest, Error>
public typealias RequestResponsePublisher = AnyPublisher<(response: HTTPURLResponse, data: Data?), Error>
public typealias RequestResultPublisher<T> = AnyPublisher<T, Error>
public typealias RequestCompletePublisher = RequestResultPublisher<Never>
public typealias RequestEventPublisher<E> = AnyPublisher<E, Error>

