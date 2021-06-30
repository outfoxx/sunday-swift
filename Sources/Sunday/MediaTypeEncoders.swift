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
import PotentCBOR
import PotentCodables
import PotentJSON


public protocol MediaTypeEncoder {
  func encode<T>(_ value: T) throws -> Data where T: Encodable
}


public struct MediaTypeEncoders {

  public static let `default` = MediaTypeEncoders.Builder().registerDefault().build()

  public struct Builder {

    private var registered: [MediaType: MediaTypeEncoder]

    public init() {
      registered = [:]
    }

    private init(registered: [MediaType: MediaTypeEncoder]) {
      self.registered = registered
    }

    public func registerDefault() -> Builder {
      return registerURL().registerData().registerJSON().registerCBOR().registerText().registerX509()
    }

    public func registerURL(
      arrayEndcoding: WWWFormURLEncoder.ArrayEncoding = .unbracketed,
      boolEncoding: WWWFormURLEncoder.BoolEncoding = .literal,
      dateEncoding: WWWFormURLEncoder.DateEncoding = .secondsSince1970,
      encoder: AnyValueEncoder = .default
    ) -> Builder {
      return register(
        encoder: WWWFormURLEncoder(
          arrayEncoding: arrayEndcoding,
          boolEncoding: boolEncoding,
          dateEncoding: dateEncoding,
          encoder: encoder
        ),
        forTypes: .wwwFormUrlEncoded
      )
    }

    public func registerData() -> Builder {
      return register(encoder: DataEncoder.default, forTypes: .octetStream)
    }

    public func registerText() -> Builder {
      return register(encoder: TextEncoder.default, forTypes: .anyText)
    }

    public func registerJSON() -> Builder {
      let encoder = JSON.Encoder()
      encoder.dateEncodingStrategy = .secondsSince1970
      return registerJSON(encoder: encoder)
    }

    public func registerJSON(encoder: JSON.Encoder) -> Builder {
      return register(encoder: encoder, forTypes: .json, .jsonStructured)
    }

    public func registerCBOR() -> Builder {
      let encoder = CBOR.Encoder()
      encoder.dateEncodingStrategy = .secondsSince1970
      return registerCBOR(encoder: encoder)
    }

    public func registerCBOR(encoder: CBOR.Encoder) -> Builder {
      return register(encoder: encoder, forTypes: .cbor)
    }

    public func registerX509() -> Builder {
      return register(encoder: DataEncoder.default, forTypes: .x509CACert, .x509UserCert)
    }

    public func register(encoder: MediaTypeEncoder, forTypes types: MediaType...) -> Builder {
      var registered = [MediaType: MediaTypeEncoder]()
      types.forEach { registered[$0] = encoder }
      return merged(registered)
    }

    public func merged(_ values: [MediaType: MediaTypeEncoder]) -> Builder {
      return Builder(registered: registered.merging(values, uniquingKeysWith: { _, last in last }))
    }

    public func build() -> MediaTypeEncoders {
      return MediaTypeEncoders(registered: registered)
    }

  }

  private let registered: [MediaType: MediaTypeEncoder]

  public func supports(for mediaType: MediaType) -> Bool {
    return registered.keys.contains { $0 ~= mediaType }
  }

  public func find(for mediaType: MediaType) throws -> MediaTypeEncoder {
    guard let encoder = registered.first(where: { key, _ in key ~= mediaType })?.value else {
      throw SundayError.requestEncodingFailed(reason: .unsupportedContentType(mediaType))
    }
    return encoder
  }

}


extension JSON.Encoder: MediaTypeEncoder {}


extension CBOR.Encoder: MediaTypeEncoder {}


public struct DataEncoder: MediaTypeEncoder {

  public static let `default` = DataEncoder()

  enum Error: Swift.Error {
    case translationNotSupported
  }

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {
    guard let data = value as? Data else {
      throw SundayError.requestEncodingFailed(reason: .serializationFailed(
        contentType: .octetStream,
        error: Error.translationNotSupported
      ))
    }
    return data
  }

}


public struct TextEncoder: MediaTypeEncoder {

  public static let `default` = TextEncoder()

  enum Error: Swift.Error {
    case translationNotSupported
    case encodingFailed
  }

  public let encoding: String.Encoding

  public init(encoding: String.Encoding = .utf8) {
    self.encoding = encoding
  }

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {
    guard let string = value as? String else {
      throw SundayError.requestEncodingFailed(reason: .serializationFailed(
        contentType: .plain,
        error: Error.translationNotSupported
      ))
    }
    guard let encoded = string.data(using: encoding) else {
      throw SundayError.requestEncodingFailed(reason: .serializationFailed(
        contentType: .plain,
        error: Error.encodingFailed
      ))
    }
    return encoded
  }

}
