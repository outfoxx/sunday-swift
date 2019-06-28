//
//  Errors.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/27/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation


public enum ParameterEncodingFailureReason {
  case unsupportedContentType(MediaType)
  case serializationFailed(contentType: MediaType, error: Error?)
}

public enum ResponseSerializationFailureReason {
  case invalidContentType(String)
  case unsupportedContentType(MediaType)
  case inputDataNilOrZeroLength
  case stringDecodingFailed(encoding: String.Encoding)
  case serializationFailed(contentType: MediaType, error: Error?)
  case missingValue
}

public enum SundayError : Swift.Error {
  case parameterEncodingFailed(reason: ParameterEncodingFailureReason)
  case responseSerializationFailed(reason: ResponseSerializationFailureReason)
  case unexpectedEmptyResponse
  case unexpectedDataResponse
  case notFound
  case invalidURL
  case invalidTemplate
}
