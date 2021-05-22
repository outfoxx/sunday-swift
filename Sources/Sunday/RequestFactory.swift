//
//  RequestFactory.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//
//  swiftlint:disable function_parameter_count

import Combine
import Foundation


public protocol RequestFactory {

  var baseURL: URI.Template { get }

  func registerProblem(type: URL, problemType: Problem.Type)
  func registerProblem(type: String, problemType: Problem.Type)

  func request<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) -> RequestPublisher

  func response<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) -> RequestResponsePublisher

  func response(request: URLRequest) -> RequestResponsePublisher

  func result<B: Encodable, D: Decodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) -> RequestResultPublisher<D>

  func result<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) -> RequestCompletePublisher

  func eventSource<B: Encodable>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?
  ) -> EventSource

  func eventStream<B: Encodable, D>(
    method: HTTP.Method, pathTemplate: String,
    pathParameters: Parameters?, queryParameters: Parameters?, body: B?,
    contentTypes: [MediaType]?, acceptTypes: [MediaType]?,
    headers: Parameters?, eventTypes: [String: AnyTextMediaTypeDecodable]
  ) -> RequestEventPublisher<D>

  func close(cancelOutstandingRequests: Bool)

}
