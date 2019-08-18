//
//  MediaTypeEncoders.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Alamofire
import Foundation
import PotentCBOR
import PotentCodables
import PotentJSON


public protocol MediaTypeEncoder {
  func encode<T>(_ value: T) throws -> Data where T: Encodable
}

public class MediaTypeEncoders {

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
      return registerURL().registerData().registerJSON().registerCBOR()
    }

    public func registerURL(encoder: AnyValueEncoder = .default, encoding: URLEncoding = .default) -> Builder {
      return register(encoder: ParameterEncodingEncoder(encoder: encoder, encoding: encoding), forTypes: .wwwFormUrlEncoded)
    }

    public func registerData() -> Builder {
      return register(encoder: DataEncoder(), forTypes: .octetStream)
    }

    public func registerJSON() -> Builder {
      let encoder = JSON.Encoder()
      encoder.dateEncodingStrategy = .millisecondsSince1970
      return registerJSON(encoder: encoder)
    }

    public func registerJSON(encoder: JSON.Encoder) -> Builder {
      return register(encoder: encoder, forTypes: .json, .jsonStructured)
    }

    public func registerCBOR() -> Builder {
      let encoder = CBOR.Encoder()
      encoder.dateEncodingStrategy = .millisecondsSince1970
      return registerCBOR(encoder: encoder)
    }

    public func registerCBOR(encoder: CBOR.Encoder) -> Builder {
      return register(encoder: encoder, forTypes: .cbor)
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

  private var registered = [MediaType: MediaTypeEncoder]()

  private init(registered: [MediaType: MediaTypeEncoder]) {
    self.registered = registered
  }

  public func register(encoding: MediaTypeEncoder, forTypes types: MediaType...) {
    types.forEach { registered[$0] = encoding }
  }

  public func find(for mediaType: MediaType) throws -> MediaTypeEncoder {
    guard let encoder = registered.first(where: { key, _ in key ~= mediaType })?.value else {
      throw SundayError.parameterEncodingFailed(reason: .unsupportedContentType(mediaType))
    }
    return encoder
  }

}


extension JSON.Encoder: MediaTypeEncoder {}


extension CBOR.Encoder: MediaTypeEncoder {}


public struct DataEncoder: MediaTypeEncoder {

  enum Error: Swift.Error {
    case translationNotSupported
  }

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {
    guard let data = value as? Data else {
      throw SundayError.responseSerializationFailed(reason: .serializationFailed(contentType: .octetStream, error: Error.translationNotSupported))
    }
    return data
  }

}


public struct TextEncoder: MediaTypeEncoder {

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
      throw SundayError.responseSerializationFailed(reason: .serializationFailed(contentType: .plain, error: Error.translationNotSupported))
    }
    guard let encoded = string.data(using: encoding) else {
      throw SundayError.responseSerializationFailed(reason: .serializationFailed(contentType: .plain, error: Error.encodingFailed))
    }
    return encoded
  }

}
