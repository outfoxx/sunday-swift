//
//  URLSessions.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


public extension URLSession {

  static func create(configuration: URLSessionConfiguration,
                     serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
                     delegate: URLSessionDelegate? = nil, delegateQueue: OperationQueue? = nil) -> URLSession {
    let localDelegate =  SessionDelegate(delegate: delegate, serverTrustPolicyManager: serverTrustPolicyManager)
    return URLSession(configuration: configuration, delegate: localDelegate, delegateQueue: delegateQueue)
  }

  func dataTaskValidatedPublisher(request: URLRequest) -> AnyPublisher<(response: HTTPURLResponse, data: Data?), Error> {
    return dataTaskPublisher(for: request)
      .tryMap { (data, response) in

        guard let httpResponse = response as? HTTPURLResponse else {
          throw URLError(.badServerResponse)
        }
        
        if 400 ..< 600 ~= httpResponse.statusCode {
          throw URLError(.badServerResponse)
        }

        return (httpResponse, data)
      }
      .eraseToAnyPublisher()
  }

  func dataTaskStreamPublisher(request: URLRequest) -> DataTaskStreamPublisher {
    return DataTaskStreamPublisher(session: self, request: request)
  }

  enum DataTaskStreamEvent {
    case connect(HTTPURLResponse)
    case data(Data)
  }

  struct DataTaskStreamPublisher: Publisher {
    
    public typealias Output = DataTaskStreamEvent
    public typealias Failure = Error
    
    private let session: URLSession
    private let request: URLRequest
    
    public init(session: URLSession, request: URLRequest) {
      self.session = session
      self.request = request
    }
    
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
      let subscription = Subscription<S>(parent: self, subscriber: subscriber)
      subscriber.receive(subscription: subscription)
    }
    
  }
  
}


private extension URLSession.DataTaskStreamPublisher {
  
  final class Subscription<S: Subscriber>: Combine.Subscription where S.Input == Output, S.Failure == Failure {
    
    final class Delegate: NSObject, URLSessionDataDelegate {
      
      let subscription: Subscription
      
      init(subscription: Subscription) {
        self.subscription = subscription
      }
      
      public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        subscription.handleComplete(error: error)
      }
      
      public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
          subscription.handleComplete(error: SundayError.invalidHTTPResponse)
          completionHandler(.cancel)
          return
        }
        
        if 400 ..< 600 ~= httpResponse.statusCode {
          let error = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: httpResponse, data: nil))
          subscription.handleComplete(error: error)
          completionHandler(.cancel)
          return
        }
        
        subscription.handleResponse(response: httpResponse)
        
        completionHandler(.allow)
      }
      
      public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        subscription.handleData(data: data)
      }
      
    }
    
    private var lock = os_unfair_lock_s()
    private var parent: URLSession.DataTaskStreamPublisher?
    private var subscriber: S?
    
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var demand: Subscribers.Demand = .none
    
    init(parent: URLSession.DataTaskStreamPublisher, subscriber: S) {
      self.parent = parent
      self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
      os_unfair_lock_lock(&lock)
      defer {
        os_unfair_lock_unlock(&lock)
      }
      
      guard demand > 0, let parent = self.parent else {
        return
      }
      
      if task == nil {
        session = URLSession(configuration: parent.session.configuration, delegate: Delegate(subscription: self), delegateQueue: nil)
        task = session!.dataTask(with: parent.request)
      }
      
      self.demand += demand
      
      task!.resume()
    }
    
    func handleResponse(response: HTTPURLResponse) {
      os_unfair_lock_lock(&lock)
      defer {
        os_unfair_lock_unlock(&lock)
      }
      
      guard demand > 0, let subscriber = subscriber else {
        return
      }
      
      demand += subscriber.receive(.connect(response))
    }
    
    func handleData(data: Data) {
      os_unfair_lock_lock(&lock)
      defer {
        os_unfair_lock_unlock(&lock)
      }
      
      guard demand > 0, let subscriber = subscriber else {
        return
      }
      
      demand += subscriber.receive(.data(data))
    }
    
    func handleComplete(error: Error?) {
      os_unfair_lock_lock(&lock)
      defer {
        os_unfair_lock_unlock(&lock)
      }
      
      guard demand > 0, let subscriber = subscriber else {
        return
      }
      
      _cancel()
      
      if let error = error {
        subscriber.receive(completion: .failure(error))
      }
      else {
        subscriber.receive(completion: .finished)
      }
    }
    
    func _cancel()  {
      task?.cancel()
      session?.invalidateAndCancel()
      
      parent = nil
      subscriber = nil
      task = nil
      session = nil
    }
    
    func cancel() {
      os_unfair_lock_lock(&lock)
      defer {
        os_unfair_lock_unlock(&lock)
      }
      
      _cancel()
    }
    
  }
  
}

