//
//  DataTaskStreamPublisherTests.swift
//  
//
//  Created by Kevin Wooten on 8/6/20.
//

import Foundation
import Sunday
import SundayServer
import XCTest


class DataTaskStreamPublisherTests: XCTestCase {
  
  static let server = try! RoutingHTTPServer(port: .any, localOnly: true) {
    Path("/regular") {
      GET { _, res in
        res.start(status: .ok, headers: [:])
        res.send(body: Data(count: 1000), final: false)
        Thread.sleep(forTimeInterval: 0.1)
        res.send(body: Data(count: 1000), final: false)
        Thread.sleep(forTimeInterval: 0.1)
        res.send(body: Data(count: 1000), final: false)
        Thread.sleep(forTimeInterval: 0.1)
        res.send(body: Data(count: 1000), final: true)
      }
    }
    Path("/chunked") {
      GET { _, res in
        res.start(status: .ok, headers: [
          HTTP.StdHeaders.transferEncoding: ["chunked"]
        ])
        res.send(chunk: Data(count: 1000))
        Thread.sleep(forTimeInterval: 0.1)
        res.send(chunk: Data(count: 1000))
        Thread.sleep(forTimeInterval: 0.1)
        res.send(chunk: Data(count: 1000))
        Thread.sleep(forTimeInterval: 0.1)
        res.send(chunk: Data(count: 1000))
        res.finish(trailers: [:])
      }
    }
  }
  static var serverURL: URL!
  
  let session = NetworkSession(configuration: .default)
  
  override class func setUp() {
    super.setUp()
    
    serverURL = server.start()
    XCTAssertNotNil(serverURL)
    print("SERVER URL", serverURL!)
  }

  func testSimple() {
    
    let getChunkedCompleteX = expectation(description: "GET - complete")
    let getChunkedDataX = expectation(description: "GET - data")
    getChunkedDataX.expectedFulfillmentCount = 5
    
    struct Params: Codable {
      let name: String
      let cost: Double
    }
    
    var urlRequest = URLRequest(url: URL(string: "regular", relativeTo: Self.serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")
    
    let requestCancel = session.dataTaskStreamPublisher(request: urlRequest)
      .sink { completion in
        defer { getChunkedCompleteX.fulfill() }
        
        if case .failure(let error) = completion {
          XCTFail("Request failed: \(error)")
        }
        
      } receiveValue: { event in
        defer { getChunkedDataX.fulfill() }
        
        switch event {
        case .connect(let response):
          XCTAssertEqual(response.statusCode, 200)
          
        case .data(let data):
          XCTAssertEqual(data.count, 1000)
        }
      }
    
    waitForExpectations(timeout: 12) { _ in
      requestCancel.cancel()
    }
    
  }
  
  func testChunked() {
    
    let getChunkedCompleteX = expectation(description: "GET (chunked) - complete")
    let getChunkedDataX = expectation(description: "GET (chunked) - data")
    getChunkedDataX.expectedFulfillmentCount = 5
    
    struct Params: Codable {
      let name: String
      let cost: Double
    }
    
    var urlRequest = URLRequest(url: URL(string: "chunked", relativeTo: Self.serverURL)!)
    urlRequest.addValue(MediaType.json.value, forHTTPHeaderField: "accept")
    
    let requestCancel = session.dataTaskStreamPublisher(request: urlRequest)
      .sink(
        receiveCompletion: { completion in
          defer { getChunkedCompleteX.fulfill() }
          
          if case .failure(let error) = completion {
            XCTFail("Request failed: \(error)")
          }
        },
        receiveValue: { event in
          defer { getChunkedDataX.fulfill() }
          
          switch event {
          case .connect(let response):
            XCTAssertEqual(response.statusCode, 200)
            
          case .data(let data):
            XCTAssertEqual(data.count, 1000)
          }
        }
      )
    
    waitForExpectations(timeout: 12) { _ in
      requestCancel.cancel()
    }
    
  }

}
