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
