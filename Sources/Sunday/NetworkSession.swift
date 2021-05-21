//
//  NetworkSession.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


public class NetworkSession {
  
  internal let session: URLSession
  internal let delegate: NetworkSessionDelegate
  internal var taskDelegates: [URLSessionTask: URLSessionTaskDelegate] = [:]
  internal let delegateQueue = OperationQueue()
  internal let serverTrustPolicyManager: ServerTrustPolicyManager?
  internal var closed = false

  public init(configuration: URLSessionConfiguration,
              serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
              delegate externalDelegate: URLSessionDelegate? = nil) {
    self.delegate = NetworkSessionDelegate(delegate: externalDelegate)
    self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
    self.serverTrustPolicyManager = serverTrustPolicyManager
    self.delegate.owner = self
  }
  
  public typealias DataTaskPublisher = URLSession.DataTaskPublisher
  
  public func dataTaskPublisher(for request: URLRequest) -> DataTaskPublisher {
    return session.dataTaskPublisher(for: request)
  }

  public typealias DataTaskValidatedPublisher = AnyPublisher<(response: HTTPURLResponse, data: Data?), Error>
  
  public func dataTaskValidatedPublisher(request: URLRequest) -> DataTaskValidatedPublisher {
    return dataTaskPublisher(for: request)
      .tryMap { (data, response) in
        
        guard let httpResponse = response as? HTTPURLResponse else {
          throw URLError(.badServerResponse)
        }
        
        if 400 ..< 600 ~= httpResponse.statusCode {
          throw SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: httpResponse,
                                                                                     data: data))
        }
        
        return (httpResponse, data)
      }
      .eraseToAnyPublisher()
  }
  
  public func dataTaskStreamPublisher(for request: URLRequest) -> DataTaskStreamPublisher {
    return DataTaskStreamPublisher(session: self, request: request)
  }
  
  public func close(cancelOutstandingTasks: Bool) {
    if cancelOutstandingTasks {
      session.invalidateAndCancel()
    }
    else {
      session.finishTasksAndInvalidate()
    }
    closed = true
  }

}
