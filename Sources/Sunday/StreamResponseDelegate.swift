//
//  StreamResponseDelegate.swift
//  Sunday
//
//  Copyright © 2019 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import RxSwift


public enum StreamResponseEvent {
  case connect(HTTPURLResponse)
  case data(Data)
}


class StreamResponseDelegate: NSObject, URLSessionDataDelegate {

  let observer: AnyObserver<StreamResponseEvent>

  init(observer: AnyObserver<StreamResponseEvent>) {
    self.observer = observer
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error {
      observer.onError(error)
    }
    else {
      observer.onCompleted()
    }
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {

    guard let httpResponse = response as? HTTPURLResponse else {
      observer.onError(SundayError.invalidHTTPResponse)
      completionHandler(.cancel)
      return
    }

    if 400 ..< 600 ~= httpResponse.statusCode {
      let error = SundayError.responseValidationFailed(reason: .unacceptableStatusCode(response: httpResponse, data: nil))
      observer.onError(error)
      completionHandler(.cancel)
      return
    }

    observer.onNext(.connect(httpResponse))

    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    observer.onNext(.data(data))
  }

}
