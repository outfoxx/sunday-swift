//
//  Publishers.swift
//  
//
//  Created by Kevin Wooten on 8/21/20.
//

import Combine


public typealias ResultPublisher<T> = AnyPublisher<T, Error>
public typealias CompletePublisher = ResultPublisher<Never>
