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


public enum RequestEncodingFailureReason {
  case noSupportedContentTypes([MediaType])
  case noSupportedAcceptTypes([MediaType])
  case unsupportedContentType(MediaType)
  case serializationFailed(contentType: MediaType, error: Error?)
  case unsupportedHeaderParameterValue(Any)
}

public enum ResponseDecodingFailureReason {
  case invalidContentType(String)
  case unsupportedContentType(MediaType)
  case noData
  case deserializationFailed(contentType: MediaType, error: Error?)
  case missingValue
}

public enum ResponseValidationFailureReason {
  case unacceptableStatusCode(response: HTTPURLResponse, data: Data?)
}

public enum SundayError: Error {
  case requestEncodingFailed(reason: RequestEncodingFailureReason)
  case responseDecodingFailed(reason: ResponseDecodingFailureReason)
  case responseValidationFailed(reason: ResponseValidationFailureReason)
  case unexpectedEmptyResponse
  case invalidURL(URLComponents? = nil)
  case invalidHTTPResponse
  case pathParameterEncodingFailed(parameter: String, reason: Error?)
}

extension SundayError: LocalizedError {

  public var errorDescription: String? {
    switch self {
    case .requestEncodingFailed(reason: let reason):
      return "Request Encoding Failed: \(reason)"
    case .responseDecodingFailed(reason: let reason):
      return "Response Decoding Failed: \(reason)"
    case .responseValidationFailed(reason: let reason):
      return "Resonse Validation Failed: \(reason)"
    case .unexpectedEmptyResponse:
      return "Unexpected Empty Response"
    case .invalidURL(let url):
      return "Invalid URL\(url.map { " url=\($0.description)" } ?? "")"
    case .invalidHTTPResponse:
      return "Invalid HTTP Response"
    case .pathParameterEncodingFailed(parameter: let param, reason: let reason):
      return "Path Parameter Encoding Failed\(reason.map { ": \($0)" } ?? ""): param=\(param)"
    }
  }

}

extension RequestEncodingFailureReason: CustomStringConvertible {

  public var description: String {
    switch self {
    case .noSupportedContentTypes(let contentTypes):
      return "No Supported Content-Types: requires=\(contentTypes)"
    case .noSupportedAcceptTypes(let contentTypes):
      return "No Supported Accept Content-Types: requires=\(contentTypes)"
    case .unsupportedContentType(let contentType):
      return "Unsupported Content-Type: type=\(contentType)"
    case .serializationFailed(contentType: let contentType, error: let error):
      return "Serialization Failed\(error.map { ": \($0)" } ?? ""): content-type=\(contentType)"
    case .unsupportedHeaderParameterValue(let value):
      return "Unsupported Header Value: value=\(String(describing: value))"
    }
  }

}

extension ResponseDecodingFailureReason: CustomStringConvertible {

  public var description: String {
    switch self {
    case .invalidContentType(let contentType):
      return "Invalid Content-Type: type=\(contentType)"
    case .unsupportedContentType(let contentType):
      return "Unsupported Content-Type: type=\(contentType)"
    case .noData:
      return "No Data"
    case .deserializationFailed(contentType: let contentType, error: let error):
      return "Deserialization Failed\(error.map { ": \($0)" } ?? ""): content-type=\(contentType)"
    case .missingValue:
      return "Missing Value"
    }
  }
}

extension ResponseValidationFailureReason: CustomStringConvertible {

  public var description: String {
    switch self {
    case .unacceptableStatusCode(response: let response, data: let data):
      var params: [(String, String)] = [("status", "\(response.statusCode)")]
      if let url = response.url {
        params.append(("url", url.absoluteString))
      }
      params.append(("response-size", "\(data.map { "\($0)" } ?? "empty")"))
      return "Unacceptable Status Code: \(params.map { "\($0)=\($1)" }.joined(separator: ", "))"
    }
  }
}
