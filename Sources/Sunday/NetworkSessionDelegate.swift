/*
 * Copyright 2021 Outfox, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation


internal class NetworkSessionDelegate: NSObject {

  internal weak var owner: NetworkSession?
  internal weak var delegate: URLSessionDelegate?

  internal init(delegate: URLSessionDelegate?) {
    self.delegate = delegate
  }

  internal func delegate<D: URLSessionDelegate>(for task: URLSessionTask, as type: D.Type) -> D? {
    return (owner?.getTaskDelegate(for: task) as? D) ?? (delegate as? D)
  }

}

extension NetworkSessionDelegate: URLSessionDelegate {

  public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    delegate?.urlSession?(session, didBecomeInvalidWithError: error)
    owner?.getTaskDelegates().forEach { delegate in delegate.urlSession?(session, didBecomeInvalidWithError: error) }
  }

  public func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let serverTrustPolicyManager = owner?.serverTrustPolicyManager,
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
    owner?.getTaskDelegates().forEach { delegate in
      delegate.urlSessionDidFinishEvents?(forBackgroundURLSession: session)
    }
  }

#endif

}

extension NetworkSessionDelegate: URLSessionTaskDelegate {

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willBeginDelayedRequest request: URLRequest,
    completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void
  ) {
    guard
      let delegate = delegate(for: task, as: URLSessionTaskDelegate.self),
      let delegateMethod = delegate.urlSession(_:task:willBeginDelayedRequest:completionHandler:)
    else {
      return completionHandler(.continueLoading, nil)
    }
    delegateMethod(session, task, request, completionHandler)
  }

  public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
    delegate(for: task, as: URLSessionTaskDelegate.self)?
      .urlSession?(session, taskIsWaitingForConnectivity: task)
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard
      let delegate = delegate(for: task, as: URLSessionTaskDelegate.self),
      let delegateMethod = delegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)
    else {
      return completionHandler(request)
    }
    return delegateMethod(session, task, response, request, completionHandler)
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard
      let delegate = delegate(for: task, as: URLSessionTaskDelegate.self),
      let delegateMethod = delegate.urlSession(_:task:didReceive:completionHandler:)
    else {
      return completionHandler(.performDefaultHandling, nil)
    }
    return delegateMethod(session, task, challenge, completionHandler)
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    needNewBodyStream completionHandler: @escaping (InputStream?) -> Void
  ) {
    guard
      let delegate = delegate(for: task, as: URLSessionTaskDelegate.self),
      let delegateMethod = delegate.urlSession(_:task:needNewBodyStream:)
    else {
      return completionHandler(nil)
    }
    return delegateMethod(session, task, completionHandler)
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    delegate(for: task, as: URLSessionTaskDelegate.self)?
      .urlSession?(
        session,
        task: task,
        didSendBodyData: bytesSent,
        totalBytesSent: totalBytesSent,
        totalBytesExpectedToSend: totalBytesExpectedToSend
      )
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didFinishCollecting metrics: URLSessionTaskMetrics
  ) {
    delegate(for: task, as: URLSessionTaskDelegate.self)?
      .urlSession?(session, task: task, didFinishCollecting: metrics)
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    delegate(for: task, as: URLSessionTaskDelegate.self)?
      .urlSession?(session, task: task, didCompleteWithError: error)
    _ = owner?.removeTaskDelegate(for: task)
  }

}

extension NetworkSessionDelegate: URLSessionDataDelegate {

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard
      let delegate = delegate(for: dataTask, as: URLSessionDataDelegate.self),
      let delegateMethod = delegate.urlSession(_:dataTask:didReceive:completionHandler:)
    else {
      return completionHandler(.allow)
    }
    return delegateMethod(session, dataTask, response, completionHandler)
  }

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didBecome downloadTask: URLSessionDownloadTask
  ) {
    guard let delegate = delegate(for: dataTask, as: URLSessionDataDelegate.self) else {
      return
    }
    delegate.urlSession?(session, dataTask: dataTask, didBecome: downloadTask)
  }

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didBecome streamTask: URLSessionStreamTask
  ) {
    guard let delegate = delegate(for: dataTask, as: URLSessionDataDelegate.self) else {
      return
    }
    delegate.urlSession?(session, dataTask: dataTask, didBecome: streamTask)
  }

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard let delegate = delegate(for: dataTask, as: URLSessionDataDelegate.self) else {
      return
    }
    delegate.urlSession?(session, dataTask: dataTask, didReceive: data)
  }

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    willCacheResponse proposedResponse: CachedURLResponse,
    completionHandler: @escaping (CachedURLResponse?) -> Void
  ) {
    guard
      let delegate = delegate(for: dataTask, as: URLSessionDataDelegate.self),
      let delegateMethod = delegate.urlSession(_:dataTask:willCacheResponse:completionHandler:)
    else {
      return completionHandler(proposedResponse)
    }
    return delegateMethod(session, dataTask, proposedResponse, completionHandler)
  }

}

extension NetworkSessionDelegate: URLSessionDownloadDelegate {


  public func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let delegate = delegate(for: downloadTask, as: URLSessionDownloadDelegate.self) else {
      return
    }
    delegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
  }

  public func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let delegate = delegate(for: downloadTask, as: URLSessionDownloadDelegate.self) else {
      return
    }
    delegate.urlSession?(
      session,
      downloadTask: downloadTask,
      didWriteData: bytesWritten,
      totalBytesWritten: totalBytesWritten,
      totalBytesExpectedToWrite: totalBytesExpectedToWrite
    )
  }

  public func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didResumeAtOffset fileOffset: Int64,
    expectedTotalBytes: Int64
  ) {
    guard let delegate = delegate(for: downloadTask, as: URLSessionDownloadDelegate.self) else {
      return
    }
    delegate.urlSession?(
      session,
      downloadTask: downloadTask,
      didResumeAtOffset: fileOffset,
      expectedTotalBytes: expectedTotalBytes
    )
  }

}

extension NetworkSessionDelegate: URLSessionStreamDelegate {

  public func urlSession(_ session: URLSession, readClosedFor streamTask: URLSessionStreamTask) {
    guard let delegate = delegate(for: streamTask, as: URLSessionStreamDelegate.self) else {
      return
    }
    delegate.urlSession?(session, readClosedFor: streamTask)
  }

  public func urlSession(_ session: URLSession, writeClosedFor streamTask: URLSessionStreamTask) {
    guard let delegate = delegate(for: streamTask, as: URLSessionStreamDelegate.self) else {
      return
    }
    delegate.urlSession?(session, writeClosedFor: streamTask)
  }

  public func urlSession(_ session: URLSession, betterRouteDiscoveredFor streamTask: URLSessionStreamTask) {
    guard let delegate = delegate(for: streamTask, as: URLSessionStreamDelegate.self) else {
      return
    }
    delegate.urlSession?(session, betterRouteDiscoveredFor: streamTask)
  }

  public func urlSession(
    _ session: URLSession,
    streamTask: URLSessionStreamTask,
    didBecome inputStream: InputStream,
    outputStream: OutputStream
  ) {
    guard let delegate = delegate(for: streamTask, as: URLSessionStreamDelegate.self) else {
      return
    }
    delegate.urlSession?(session, streamTask: streamTask, didBecome: inputStream, outputStream: outputStream)
  }

}

extension NetworkSessionDelegate: URLSessionWebSocketDelegate {

  public func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    guard let delegate = delegate(for: webSocketTask, as: URLSessionWebSocketDelegate.self) else {
      return
    }
    delegate.urlSession?(session, webSocketTask: webSocketTask, didOpenWithProtocol: `protocol`)
  }


  public func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    guard let delegate = delegate(for: webSocketTask, as: URLSessionWebSocketDelegate.self) else {
      return
    }
    delegate.urlSession?(session, webSocketTask: webSocketTask, didCloseWith: closeCode, reason: reason)
  }

}
