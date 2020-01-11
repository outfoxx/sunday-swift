//
//  SessionDelegate.swift
//  
//
//  Created by Kevin Wooten on 12/6/19.
//

import Foundation



public class SessionDelegate: NSObject {

  public let delegate: URLSessionDelegate?
  public let serverTrustPolicyManager: ServerTrustPolicyManager?
  public var taskDelegates: [URLSessionTask: URLSessionTaskDelegate] = [:]

  public init(delegate: URLSessionDelegate?, serverTrustPolicyManager: ServerTrustPolicyManager?) {
    self.delegate = delegate
    self.serverTrustPolicyManager = serverTrustPolicyManager
  }

}

extension SessionDelegate: URLSessionDelegate {

  public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    delegate?.urlSession?(session, didBecomeInvalidWithError: error)
    taskDelegates.values.forEach { delegate in delegate.urlSession?(session, didBecomeInvalidWithError: error) }
  }

  public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let serverTrustPolicyManager = serverTrustPolicyManager,
      let serverTrustPolicy = serverTrustPolicyManager.serverTrustPolicy(forHost: challenge.protectionSpace.host),
      let serverTrust = challenge.protectionSpace.serverTrust
    else {
      return completionHandler(.performDefaultHandling, nil)
    }

    let host = challenge.protectionSpace.host

    let disposition: URLSession.AuthChallengeDisposition
    let credential: URLCredential?

    if serverTrustPolicy.evaluate(serverTrust, forHost: host) {
      disposition = .useCredential
      credential = URLCredential(trust: serverTrust)
    }
    else {
      disposition = .cancelAuthenticationChallenge
      credential = nil
    }

    completionHandler(disposition, credential)
  }

  #if !os(macOS)

  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    delegate?.urlSessionDidFinishEvents?(forBackgroundURLSession: session)
    taskDelegates.values.forEach { delegate in delegate.urlSessionDidFinishEvents?(forBackgroundURLSession: session) }
  }

  #endif

}

extension SessionDelegate: URLSessionTaskDelegate {

  @available(macOS 10.13, iOS 11, tvOS 11, watchOS 4, *)
  public func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest, completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
    guard let delegate = taskDelegates[task], let delegateMethod = delegate.urlSession(_:task:willBeginDelayedRequest:completionHandler:) else {
      guard let delegate = self.delegate as? URLSessionTaskDelegate, let delegateMethod = delegate.urlSession(_:task:willBeginDelayedRequest:completionHandler:) else {
        return completionHandler(.continueLoading, nil)
      }
      return delegateMethod(session, task, request, completionHandler)
    }
    delegateMethod(session, task, request, completionHandler)
  }

  @available(macOS 10.13, iOS 11, tvOS 11, watchOS 4, *)
  public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
    taskDelegates[task]?.urlSession?(session, taskIsWaitingForConnectivity: task)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    guard let delegate = taskDelegates[task], let delegateMethod = delegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:) else {
      guard let delegate = self.delegate as? URLSessionTaskDelegate, let delegateMethod = delegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:) else {
        return completionHandler(request)
      }
      return delegateMethod(session, task, response, request, completionHandler)
    }
    return delegateMethod(session, task, response, request, completionHandler)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard let delegate = taskDelegates[task], let delegateMethod = delegate.urlSession(_:task:didReceive:completionHandler:) else {
      guard let delegate = self.delegate as? URLSessionTaskDelegate, let delegateMethod = delegate.urlSession(_:task:didReceive:completionHandler:) else {
        return completionHandler(.performDefaultHandling, nil)
      }
      return delegateMethod(session, task, challenge, completionHandler)
    }
    return delegateMethod(session, task, challenge, completionHandler)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
    guard let delegate = taskDelegates[task], let delegateMethod = delegate.urlSession(_:task:needNewBodyStream:) else {
      guard let delegate = self.delegate as? URLSessionTaskDelegate, let delegateMethod = delegate.urlSession(_:task:needNewBodyStream:) else {
        return completionHandler(nil)
      }
      return delegateMethod(session, task, completionHandler)
    }
    return delegateMethod(session, task, completionHandler)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
    taskDelegates[task]?.urlSession?(session, task: task, didSendBodyData: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
    taskDelegates[task]?.urlSession?(session, task: task, didFinishCollecting: metrics)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    taskDelegates[task]?.urlSession?(session, task: task, didCompleteWithError: error)
  }

}

extension SessionDelegate: URLSessionDataDelegate {

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let delegate = taskDelegates[dataTask] as? URLSessionDataDelegate, let delegateMethod = delegate.urlSession(_:dataTask:didReceive:completionHandler:) else {
      guard let delegate = self.delegate as? URLSessionDataDelegate, let delegateMethod = delegate.urlSession(_:dataTask:didReceive:completionHandler:) else {
        return completionHandler(.allow)
      }
      return delegateMethod(session, dataTask, response, completionHandler)
    }
    return delegateMethod(session, dataTask, response, completionHandler)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
    guard let delegate = taskDelegates[dataTask] as? URLSessionDataDelegate else {
      return
    }
    delegate.urlSession?(session, dataTask: dataTask, didBecome: downloadTask)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
    guard let delegate = taskDelegates[dataTask] as? URLSessionDataDelegate else {
      return
    }
    delegate.urlSession?(session, dataTask: dataTask, didBecome: streamTask)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard let delegate = taskDelegates[dataTask] as? URLSessionDataDelegate else {
      return
    }
    delegate.urlSession?(session, dataTask: dataTask, didReceive: data)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
    guard let delegate = taskDelegates[dataTask] as? URLSessionDataDelegate, let delegateMethod = delegate.urlSession(_:dataTask:willCacheResponse:completionHandler:) else {
      guard let delegate = self.delegate as? URLSessionDataDelegate, let delegateMethod = delegate.urlSession(_:dataTask:willCacheResponse:completionHandler:) else {
        return completionHandler(proposedResponse)
      }
      return delegateMethod(session, dataTask, proposedResponse, completionHandler)
    }
    return delegateMethod(session, dataTask, proposedResponse, completionHandler)
  }

}

extension SessionDelegate: URLSessionDownloadDelegate {


  public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let delegate = taskDelegates[downloadTask] as? URLSessionDownloadDelegate else {
      return
    }
    delegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
  }

  public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard let delegate = taskDelegates[downloadTask] as? URLSessionDownloadDelegate else {
      return
    }
    delegate.urlSession?(session, downloadTask: downloadTask, didWriteData: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
  }

  public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
    guard let delegate = taskDelegates[downloadTask] as? URLSessionDownloadDelegate else {
      return
    }
    delegate.urlSession?(session, downloadTask: downloadTask, didResumeAtOffset: fileOffset, expectedTotalBytes: expectedTotalBytes)
  }

}

extension SessionDelegate: URLSessionStreamDelegate {

  public func urlSession(_ session: URLSession, readClosedFor streamTask: URLSessionStreamTask) {
    guard let delegate = taskDelegates[streamTask] as? URLSessionStreamDelegate else {
      return
    }
    delegate.urlSession?(session, readClosedFor: streamTask)
  }

  public func urlSession(_ session: URLSession, writeClosedFor streamTask: URLSessionStreamTask) {
    guard let delegate = taskDelegates[streamTask] as? URLSessionStreamDelegate else {
      return
    }
    delegate.urlSession?(session, writeClosedFor: streamTask)
  }

  public func urlSession(_ session: URLSession, betterRouteDiscoveredFor streamTask: URLSessionStreamTask) {
    guard let delegate = taskDelegates[streamTask] as? URLSessionStreamDelegate else {
      return
    }
    delegate.urlSession?(session, betterRouteDiscoveredFor: streamTask)
  }

  public func urlSession(_ session: URLSession, streamTask: URLSessionStreamTask, didBecome inputStream: InputStream, outputStream: OutputStream) {
    guard let delegate = taskDelegates[streamTask] as? URLSessionStreamDelegate else {
      return
    }
    delegate.urlSession?(session, streamTask: streamTask, didBecome: inputStream, outputStream: outputStream)
  }

}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension SessionDelegate: URLSessionWebSocketDelegate {

  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    guard let delegate = taskDelegates[webSocketTask] as? URLSessionWebSocketDelegate else {
      return
    }
    delegate.urlSession?(session, webSocketTask: webSocketTask, didOpenWithProtocol: `protocol`)
  }


  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    guard let delegate = taskDelegates[webSocketTask] as? URLSessionWebSocketDelegate else {
      return
    }
    delegate.urlSession?(session, webSocketTask: webSocketTask, didCloseWith: closeCode, reason: reason)
  }

}
