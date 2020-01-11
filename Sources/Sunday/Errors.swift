//
//  Errors.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public enum ParameterEncodingFailureReason {
  case unsupportedContentType(MediaType)
  case serializationFailed(contentType: MediaType, error: Error?)
}

public enum RequestEncodingFailureReason {
  case noSupportedContentType([MediaType])
  case unsupportedContentType(MediaType)
  case serializationFailed(contentType: MediaType, error: Error?)
}

public enum ResponseDecodingFailureReason {
  case invalidContentType(String)
  case unsupportedContentType(MediaType)
  case inputDataNilOrZeroLength
  case stringDecodingFailed(encoding: String.Encoding)
  case serializationFailed(contentType: MediaType, error: Error?)
  case missingValue
}

public enum ResponseValidationFailureReason {
  case unacceptableStatusCode(response: HTTPURLResponse, data: Data?)
}

public enum SundayError: Swift.Error {
  case parameterEncodingFailed(reason: ParameterEncodingFailureReason)
  case requestEncodingFailed(reason: RequestEncodingFailureReason)
  case responseDecodingFailed(reason: ResponseDecodingFailureReason)
  case responseValidationFailed(reason: ResponseValidationFailureReason)
  case unexpectedEmptyResponse
  case unexpectedDataResponse
  case notFound
  case invalidURL(URLComponents? = nil)
  case invalidTemplate
  case unknownNetworkError
  case invalidHTTPResponse
}
