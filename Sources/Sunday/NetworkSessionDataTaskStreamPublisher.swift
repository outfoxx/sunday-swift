//
//  NetworkSessionDataTaskStreamPublisher.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Combine


public extension NetworkSession {

  enum DataTaskStreamEvent {
    case connect(HTTPURLResponse)
    case data(Data)
  }

  struct DataTaskStreamPublisher: Publisher {
    
    public typealias Output = DataTaskStreamEvent
    public typealias Failure = Error
    
    private let session: NetworkSession
    private let request: URLRequest
    
    public init(session: NetworkSession, request: URLRequest) {
      self.session = session
      self.request = request
    }
    
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
      let subscription = Subscription<S>(parent: self, subscriber: subscriber)
      subscriber.receive(subscription: subscription)
    }
    
  }
  
}


private extension NetworkSession.DataTaskStreamPublisher {
  
  final class Subscription<S: Subscriber>: Combine.Subscription where S.Input == Output, S.Failure == Failure {
    
    final class Delegate: NSObject, URLSessionDataDelegate {
      
      let subscription: Subscription
      
      init(subscription: Subscription) {
        self.subscription = subscription
      }
      
      public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        subscription.handleComplete(error: error)
      }
      
      public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                             didReceive response: URLResponse,
                             completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        
        guard let httpResponse = response as? HTTPURLResponse else {
          subscription.handleComplete(error: SundayError.invalidHTTPResponse)
          completionHandler(.cancel)
          return
        }
        
        if 400 ..< 600 ~= httpResponse.statusCode {
          let error = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: httpResponse,
                                                                                           data: nil))
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
    
    private var lock = NSRecursiveLock()
    private var parent: NetworkSession.DataTaskStreamPublisher?
    private var subscriber: S?
    
    private var task: URLSessionDataTask?
    private var demand: Subscribers.Demand = .none
    
    init(parent: NetworkSession.DataTaskStreamPublisher, subscriber: S) {
      self.parent = parent
      self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
      lock.lock()
      defer {
        lock.unlock()
      }
      
      guard demand > 0, let parent = self.parent else {
        return
      }
      
      if task == nil {
        task = parent.session.session.dataTask(with: parent.request)
        parent.session.taskDelegates[task!] = Delegate(subscription: self)
      }
      
      self.demand += demand
      
      task!.resume()
    }
    
    func handleResponse(response: HTTPURLResponse) {
      lock.lock()
      defer {
        lock.unlock()
      }

      guard demand > 0, let subscriber = subscriber else {
        return
      }
      
      demand += subscriber.receive(.connect(response))
    }
    
    func handleData(data: Data) {
      lock.lock()
      defer {
        lock.unlock()
      }

      guard demand > 0, let subscriber = subscriber else {
        return
      }
      
      demand += subscriber.receive(.data(data))
    }
    
    func handleComplete(error: Error?) {
      lock.lock()
      defer {
        lock.unlock()
       }

      guard let subscriber = subscriber else {
        return
      }
      
      if let error = error {
        subscriber.receive(completion: .failure(error))
      }
      else {
        subscriber.receive(completion: .finished)
      }
      
      cleanup()
    }
    
    func cancel() {
      lock.lock()
      defer {
        lock.unlock()
      }

      task?.cancel()
      task = nil

      cleanup()
    }
    
    private func cleanup()  {
      parent = nil
      subscriber = nil
    }

  }
  
}

