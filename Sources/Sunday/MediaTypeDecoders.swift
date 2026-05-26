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
import PotentJSON


public protocol MediaTypeDecoder: Sendable {
  func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable
}

public protocol TextMediaTypeDecoder: MediaTypeDecoder {
  func decode<T: Decodable>(_ type: T.Type, from data: String) throws -> T
}


public struct MediaTypeDecoders: Sendable {

  public static let `default` = MediaTypeDecoders.Builder().registerDefault().build()

  public struct Builder: Sendable {

    private var registered: [MediaType: MediaTypeDecoder]

    public init() {
      registered = [:]
    }

    private init(registered: [MediaType: MediaTypeDecoder]) {
      self.registered = registered
    }

    public func registerDefault() -> Builder {
      return self
        .registerData()
        .registerJSON()
        .registerCBOR()
        .registerEventStream()
        .registerText()
        .registerX509()
    }

    public func registerData() -> Builder {
      return register(decoder: DataDecoder.default, forTypes: .octetStream)
    }

    public func registerText() -> Builder {
      return register(decoder: TextDecoder.default, forTypes: .anyText)
    }

    public func registerJSON() -> Builder {
      let decoder = JSON.Decoder()
      decoder.dateDecodingStrategy = .secondsSince1970
      return registerJSON(decoder: decoder)
    }

    /**
     * Registers a JSON decoder.
     *
     * Configure the decoder before registration and do not mutate it afterward.
     * Sunday retains and uses the decoder directly during synchronous decoding.
     */
    public func registerJSON(decoder: JSON.Decoder) -> Builder {
      return register(decoder: JSONMediaTypeDecoder(decoder: decoder), forTypes: .json, .jsonStructured)
    }

    public func registerCBOR() -> Builder {
      let decoder = CBOR.Decoder()
      decoder.untaggedDateDecodingStrategy = .secondsSince1970
      return registerCBOR(decoder: decoder)
    }

    /**
     * Registers a CBOR decoder.
     *
     * Configure the decoder before registration and do not mutate it afterward.
     * Sunday retains and uses the decoder directly during synchronous decoding.
     */
    public func registerCBOR(decoder: CBOR.Decoder) -> Builder {
      return register(decoder: CBORMediaTypeDecoder(decoder: decoder), forTypes: .cbor)
    }

    public func registerX509() -> Builder {
      return register(decoder: DataDecoder.default, forTypes: .x509CACert, .x509UserCert)
    }

    public func registerEventStream() -> Builder {
      return register(decoder: DataDecoder.default, forTypes: .eventStream)
    }

    public func register(decoder: MediaTypeDecoder, forTypes types: MediaType...) -> Builder {
      var registered = [MediaType: MediaTypeDecoder]()
      types.forEach { registered[$0] = decoder }
      return merged(registered)
    }

    public func merged(_ values: [MediaType: MediaTypeDecoder]) -> Builder {
      return Builder(registered: registered.merging(values, uniquingKeysWith: { _, last in last }))
    }

    public func build() -> MediaTypeDecoders {
      return MediaTypeDecoders(registered: registered)
    }

  }

  private let registered: [MediaType: MediaTypeDecoder]

  public func supports(for mediaType: MediaType) -> Bool {
    return registered.keys.contains { $0 ~= mediaType }
  }

  public func find(for mediaType: MediaType) throws -> MediaTypeDecoder {
    guard let decoder = registered.first(where: { key, _ in key ~= mediaType })?.value else {
      throw SundayError.responseDecodingFailed(reason: .unsupportedContentType(mediaType))
    }
    return decoder
  }

}


// PotentCodables decoders expose mutable configuration, but this wrapper does not expose
// the configured decoder after registration. Decoding uses the private instance directly.
private struct JSONMediaTypeDecoder: TextMediaTypeDecoder {

  nonisolated(unsafe) private let decoder: JSON.Decoder

  init(decoder: JSON.Decoder) {
    self.decoder = decoder
  }

  func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
    return try decoder.decode(type, from: data)
  }

  func decode<T>(_ type: T.Type, from data: String) throws -> T where T: Decodable {
    return try decoder.decode(type, from: data)
  }

}


// PotentCodables decoders expose mutable configuration, but this wrapper does not expose
// the configured decoder after registration. Decoding uses the private instance directly.
private struct CBORMediaTypeDecoder: MediaTypeDecoder {

  nonisolated(unsafe) private let decoder: CBOR.Decoder

  init(decoder: CBOR.Decoder) {
    self.decoder = decoder
  }

  func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
    return try decoder.decode(type, from: data)
  }

}


public struct DataDecoder: MediaTypeDecoder {

  public static let `default` = DataDecoder()

  enum Error: Swift.Error {
    case translationNotSupported
  }

  public func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
    guard type == Data.self else {
      throw SundayError.responseDecodingFailed(reason: .deserializationFailed(
        contentType: .octetStream,
        error: Error.translationNotSupported
      ))
    }
    // swiftlint:disable:next force_cast
    return (data as! T)
  }

}


public struct TextDecoder: MediaTypeDecoder, TextMediaTypeDecoder {

  public static let `default` = TextDecoder()

  enum Error: Swift.Error {
    case translationNotSupported
  }

  public func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
    guard type == String.self else {
      throw SundayError.responseDecodingFailed(reason: .deserializationFailed(
        contentType: .plain,
        error: Error.translationNotSupported
      ))
    }
    // swiftlint:disable:next force_cast
    return (String(data: data, encoding: .utf8) as! T)
  }

  public func decode<T>(_ type: T.Type, from data: String) throws -> T where T: Decodable {
    guard type == String.self else {
      throw SundayError.responseDecodingFailed(reason: .deserializationFailed(
        contentType: .plain,
        error: Error.translationNotSupported
      ))
    }
    // swiftlint:disable:next force_cast
    return (data as! T)
  }

}
