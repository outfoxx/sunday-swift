//
//  MediaTypeCodecTests.swift
//  Sunday
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import XCTest
@testable import Sunday


class MediaTypeCodecTests : XCTestCase {
  
  func testDataDecoderDecodesData() throws {
    
    let dataDecoder = DataDecoder()
    
    let data = Data(count: 100)
    
    let decoded = try dataDecoder.decode(Data.self, from: data)
    
    XCTAssertEqual(decoded, data)
  }
  
  func testDataDecoderFailsForAnythingElse() throws {
    
    let dataDecoder = DataDecoder()
    
    let data = Data(count: 100)
    
    XCTAssertThrowsError(
      try dataDecoder.decode(Int.self, from: data)
    ) { error in
      
      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.deserializationFailed(contentType: let contentType, error: let cause) = reason
      else {
        return XCTFail("unexpected error")
      }
      
      XCTAssertEqual(contentType, .octetStream)
      XCTAssertTrue(cause.debugDescription.contains("translationNotSupported"))
    }
    
  }
  
  func testDataEncoderEncodesData() throws {
    
    let dataEncoder = DataEncoder()
    
    let data = Data(count: 100)
    
    let encoded = try dataEncoder.encode(data)
    
    XCTAssertEqual(encoded, data)
  }
  
  func testDataEncoderFailsForAnythingElse() throws {
    
    let dataEncoder = DataEncoder()
    
    XCTAssertThrowsError(
      try dataEncoder.encode(10)
    ) { error in
      
      guard
        case SundayError.requestEncodingFailed(reason: let reason) = error,
        case RequestEncodingFailureReason.serializationFailed(contentType: let contentType, error: let cause) = reason
      else {
        return XCTFail("unexpected error")
      }
      
      XCTAssertEqual(contentType, .octetStream)
      XCTAssertTrue(cause.debugDescription.contains("translationNotSupported"))
    }
    
  }

  func testTextDecoderDecodesTextString() throws {
    
    let textDecoder = TextDecoder()
    
    let text = "Here is some test"
    
    let decoded = try textDecoder.decode(String.self, from: text)
    
    XCTAssertEqual(decoded, text)
  }
  
  func testTextDecoderDecodesTextData() throws {
    
    let textDecoder = TextDecoder()
    
    let text = "Here is some test"
    
    let decoded = try textDecoder.decode(String.self, from: text.data(using: .utf8)!)
    
    XCTAssertEqual(decoded, text)
  }
  
  func testTextDecoderFailsDecodingDataForAnythingElse() throws {
    
    let textDecoder = TextDecoder()
    
    let text = "here is some text"
    
    XCTAssertThrowsError(
      try textDecoder.decode(Int.self, from: text.data(using: .utf8)!)
    ) { error in
      
      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.deserializationFailed(contentType: let contentType, error: let cause) = reason
      else {
        return XCTFail("unexpected error")
      }
      
      XCTAssertEqual(contentType, .plain)
      XCTAssertTrue(cause.debugDescription.contains("translationNotSupported"))
    }
    
  }
  
  func testTextDecoderFailsDecodingTextForAnythingElse() throws {
    
    let textDecoder = TextDecoder()
    
    let text = "here is some text"
    
    XCTAssertThrowsError(
      try textDecoder.decode(Int.self, from: text)
    ) { error in
      
      guard
        case SundayError.responseDecodingFailed(reason: let reason) = error,
        case ResponseDecodingFailureReason.deserializationFailed(contentType: let contentType, error: let cause) = reason
      else {
        return XCTFail("unexpected error")
      }
      
      XCTAssertEqual(contentType, .plain)
      XCTAssertTrue(cause.debugDescription.contains("translationNotSupported"))
    }
    
  }
  
  func testTextEncoderEncodesText() throws {
    
    let textEncoder = TextEncoder()
    
    let text = "Here is some test"
    
    let encoded = try textEncoder.encode(text)
    
    XCTAssertEqual(encoded, text.data(using: .utf8))
  }
  
  func testTextEncoderFailsEncodingForAnythingElse() throws {
    
    let textEncoder = TextEncoder()
    
    XCTAssertThrowsError(
      try textEncoder.encode(100)
    ) { error in
      
      guard
        case SundayError.requestEncodingFailed(reason: let reason) = error,
        case RequestEncodingFailureReason.serializationFailed(contentType: let contentType, error: let cause) = reason
      else {
        return XCTFail("unexpected error")
      }
      
      XCTAssertEqual(contentType, .plain)
      XCTAssertTrue(cause.debugDescription.contains("translationNotSupported"))
    }
    
  }

}
