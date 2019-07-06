//
//  DataRequest.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/12/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation
import Alamofire
import RxSwift


extension DataRequest {

  func observe<D: Decodable>(mediaTypeDecoders: MediaTypeDecoders, queue: DispatchQueue? = nil) -> Single<D> {

    return Single.create { completer in
      let inFlight = self.responseByContentType(mediaTypeDecoders: mediaTypeDecoders, queue: queue) { (response: DataResponse<D>) in
        switch response.result {
        case let .success(value):
          completer(.success(value))
        case let .failure(value):
          completer(.error(value))
        }
      }
      return Disposables.create {
        inFlight.cancel()
      }
    }

  }

  func complete(mediaTypeDecoders: MediaTypeDecoders, queue: DispatchQueue? = nil) -> Completable {

    return Completable.create { completer in
      let inFlight = self.responseByContentType(mediaTypeDecoders: mediaTypeDecoders, queue: queue) { (response: DataResponse<Empty>) in
        switch response.result {
        case .success(_):
          completer(.completed)
        case let .failure(value):
          completer(.error(value))
        }
      }
      return Disposables.create {
        inFlight.cancel()
      }
    }

  }

  @discardableResult
  func responseByContentType<D>(mediaTypeDecoders: MediaTypeDecoders, queue: DispatchQueue? = nil, completionHandler: @escaping (DataResponse<D>) -> Void) -> Self where D : Decodable {

    let responseSerializer = DataResponseSerializer<D> { _, response, data, error -> Result<D> in

      guard error == nil else { return .failure(error!) }

      guard let response = response, !emptyDataStatusCodes.contains(response.statusCode) else {
        guard D.self == Empty.self else {
          return .failure(SundayError.unexpectedEmptyResponse)
        }
        return .success(Empty.instance as! D)
      }

      guard let validData = data, !validData.isEmpty else {
        return .failure(AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength))
      }

      guard
        let contentTypeName = response.value(forHTTPHeaderField: HTTP.StdHeaders.contentType),
        let contentType = MediaType(contentTypeName)
      else {
        let badType = response.value(forHTTPHeaderField: HTTP.StdHeaders.contentType) ?? "none"
        return .failure(SundayError.responseSerializationFailed(reason: .invalidContentType(badType)))
      }

      do {
        let mediaTypeDecoder = try mediaTypeDecoders.find(for: contentType)

        // Check for detailed client error responses
        if (400 ..< 600).contains(response.statusCode) {

          // Attempt to decode the value as a `problem+json`
          guard let problem = try? mediaTypeDecoder.decode(Problem.self, from: validData) else {
            return .failure(AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: response.statusCode)))
          }

          return .failure(problem)
        }

        guard let value = try mediaTypeDecoder.decode(D.self, from: validData) as D? else {
          return .failure(SundayError.responseSerializationFailed(reason: .missingValue))
        }

        return .success(value)
      }
      catch {
        return .failure(error)
      }
    }

    return self.response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
  }

}
