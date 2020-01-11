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
import RxSwift


public extension URLSession {

  static func create(configuration: URLSessionConfiguration,
                     serverTrustPolicyManager: ServerTrustPolicyManager? = nil,
                     delegate: URLSessionDelegate? = nil, delegateQueue: OperationQueue? = nil) -> URLSession {
    let localDelegate =  SessionDelegate(delegate: delegate, serverTrustPolicyManager: serverTrustPolicyManager)
    return URLSession(configuration: configuration, delegate: localDelegate, delegateQueue: delegateQueue)
  }

  struct RequestOptions: OptionSet {
    public var rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let noFollowRedirects = RequestOptions(rawValue: 1 << 0)
  }

  func response(request: URLRequest, options: RequestOptions = []) -> Single<(response: HTTPURLResponse, data: Data?)> {
    return Single.create { observer in

      guard let delegate = self.delegate as? SessionDelegate else {
        fatalError("URLSession.response provided by Sunday requires the SundayURLSessionDelegate on URLSession")
      }

      let task = self.dataTask(with: request) { data, response, error in

        if let error = error {
          observer(.error(error))
          return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
          observer(.error(SundayError.invalidHTTPResponse))
          return
        }

        if 400 ..< 600 ~= httpResponse.statusCode {
          let error = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: httpResponse, data: data))
          observer(.error(error))
          return
        }

        observer(.success((httpResponse, data)))
      }

      if !options.isEmpty {

        delegate.taskDelegates[task] = ResponseDelegate(options: options)
      }

      task.resume()

      return Disposables.create {
        task.cancel()
        delegate.taskDelegates.removeValue(forKey: task)
      }
    }
  }

  func streamResponse(request: URLRequest) -> Observable<StreamResponseEvent> {

    guard let delegate = self.delegate as? SessionDelegate else {
      fatalError("URLSession.streamResponse provided by Sunday requires the SundayURLSessionDelegate on URLSession")
    }

    return Observable.create { observer in

      let task = self.dataTask(with: request)

      delegate.taskDelegates[task] = StreamResponseDelegate(observer: observer)

      task.resume()

      return Disposables.create {
        task.cancel()
        delegate.taskDelegates.removeValue(forKey: task)
      }
    }
  }

}
