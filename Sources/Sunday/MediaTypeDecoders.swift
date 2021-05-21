//
//  MediaTypeDecoders.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCBOR
import PotentJSON


public protocol MediaTypeDecoder {
  func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable
}

public protocol TextMediaTypeDecoder : MediaTypeDecoder {
  func decode<T: Decodable>(_ type: T.Type, from data: String) throws -> T
}


public struct MediaTypeDecoders {

  public static let `default` = MediaTypeDecoders.Builder().registerDefault().build()

  public struct Builder {

    private var registered: [MediaType: MediaTypeDecoder]

    public init() {
      registered = [:]
    }

    private init(registered: [MediaType: MediaTypeDecoder]) {
      self.registered = registered
    }

    public func registerDefault() -> Builder {
      return registerData().registerJSON().registerCBOR().registerText()
    }

    public func registerData() -> Builder {
      return register(decoder: DataDecoder(), forTypes: .octetStream)
    }
    
    public func registerText() -> Builder {
      return register(decoder: TextDecoder(), forTypes: .anyText)
    }

    public func registerJSON() -> Builder {
      let decoder = JSON.Decoder()
      decoder.dateDecodingStrategy = .secondsSince1970
      return registerJSON(decoder: decoder)
    }

    public func registerJSON(decoder: JSON.Decoder) -> Builder {
      return register(decoder: decoder, forTypes: .json, .jsonStructured)
    }

    public func registerCBOR() -> Builder {
      let decoder = CBOR.Decoder()
      decoder.untaggedDateDecodingStrategy = .secondsSince1970
      return registerCBOR(decoder: decoder)
    }

    public func registerCBOR(decoder: CBOR.Decoder) -> Builder {
      return register(decoder: decoder, forTypes: .cbor)
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


extension JSON.Decoder: TextMediaTypeDecoder {}


extension CBOR.Decoder: MediaTypeDecoder {}


public struct DataDecoder: MediaTypeDecoder {
  
  public static let `default` = DataDecoder()
  
  enum Error: Swift.Error {
    case translationNotSupported
  }
  
  public func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
    guard type == Data.self else {
      throw SundayError.responseDecodingFailed(reason: .deserializationFailed(contentType: .octetStream,
                                                                              error: Error.translationNotSupported))
    }
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
      throw SundayError.responseDecodingFailed(reason: .deserializationFailed(contentType: .plain,
                                                                              error: Error.translationNotSupported))
    }
    return (String(data: data, encoding: .utf8) as! T)
  }

  public func decode<T>(_ type: T.Type, from data: String) throws -> T where T : Decodable {
    guard type == String.self else {
      throw SundayError.responseDecodingFailed(reason: .deserializationFailed(contentType: .plain,
                                                                              error: Error.translationNotSupported))
    }
    return (data as! T)
  }
  
}
