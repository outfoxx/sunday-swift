//
//  SundayTests.swift
//  SundayTests
//
//  Created by Kevin Wooten on 6/16/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import XCTest
import Alamofire
import PromiseKit
import RxSwift
//import Embassy
//import EnvoyAmbassador
//@testable import Sunday
//
//class SundayTests: XCTestCase {
//
//  func testRequest() throws {
//
//    let testServerManager = TestServerManager()
//    testServerManager.start()
//
//    let x = expectation(description: "Done")
//
//    let target = EndpointTarget(baseURL: "http://localhost:\(testServerManager.server.listenAddress.port)/api/v1")
//    let simAPI = SimulationAPI(requestManager: NetworkRequestManager(target: target))
//
//    firstly {
//      try simAPI.adminAccessToken().promise()
//    }
//    .then { accessToken -> Promise<[Tenant]> in
//      print("access token = \(accessToken)")
//      try target.addSessionManager(named: .custom("auth"), adaptedBy: Authorizer(accessToken: accessToken))
//
//      let authTarget = try target.configured(with: .custom("auth"))
//
//      return try authTarget.bind(AdminAPI.self).listTenants(offset: nil, limit: nil).promise()
//    }
//    .done { tenants in
//      print("Tenants: \(tenants)")
//    }
//    .catch { error in
//      print("Error listing tenants: \(error)")
//    }
//    .finally {
//      x.fulfill()
//    }
//
//    waitForExpectations(timeout: 500, handler: nil)
//  }
//
//  func testEvents() {
//
//    let testServerManager = TestServerManager()
//    testServerManager.start()
//
//    let x = expectation(description: "wait for events")
//    x.expectedFulfillmentCount = 3
//
//    let target = NetworkEndpointTarget(configuration: EndpointConfiguration(baseURL: "http://localhost:\(testServerManager.server.listenAddress.port)/"))
//    let deviceAPI = target.bind(DeviceAPI.self)
//
//    let eventsSub = deviceAPI.events()
//      .observe()
//      .take(3)
//      .subscribe(
//        onNext: { event -> Void in print("event = \(event)"); x.fulfill() }
//      )
//
//    waitForExpectations(timeout: 10, handler: nil)
//
//    eventsSub.dispose()
//  }
//
//}
//
//
//public struct SimulationAPI : EndpointManager {
//
//  public let requestManager: RequestManager
//
//  public init(requestManager: RequestManager) {
//    self.requestManager = requestManager
//  }
//
//  public func adminAccessToken() throws -> Single<String> {
//    return try requestManager.build(method: .post, pathTemplate: "admins/access",
//                                      pathParameters: nil, queryParameters: nil, body: nil as Empty?,
//                                      contentType: nil, acceptTypes: nil, headers: nil)
//  }
//
//  func tenantsSetupAccount(tenantId: String, accountId: String, accountCertReq: Data) throws -> Single<String> {
//    let pathParameters: Parameters = [
//      "tenantId": tenantId
//    ]
//    let body: [String: String] = [
//      "accountId": accountId,
//      "accountCertReq": accountCertReq.base64EncodedString()
//    ]
//    return try requestManager.build(method: .post, pathTemplate: "tenants/{tenantId}/setup-account",
//                                    pathParameters: pathParameters, queryParameters: nil, body: body,
//                                    contentType: nil, acceptTypes: nil, headers: nil)
//  }
//
//}
//
//
//private class TestServerManager {
//
//  let loop = try! SelectorEventLoop(selector: try! KqueueSelector())
//
//  let router = Router()
//
//  let server: DefaultHTTPServer
//
//  init() {
//
//    router["^/events$"] = SWGIWebApp { environ, start, send in
//
//      let loop = environ["embassy.event_loop"] as! EventLoop
//
//      start("200 OK", [
//        ("Content-Type", MediaType.eventStream.value)
//      ])
//
//      func sendText(_ value: String) {
//        send(value.data(using: .utf8)!)
//      }
//
//      sendText("\n")
//
//      loop.call(withDelay: 0.150) {
//        sendText(
//          """
//          id: 123
//          event: dlv
//          data: {"messageId":"1a2b3c", "occurredAt": 0, "sent": 10}
//
//
//          """
//        )
//      }
//
//      loop.call(withDelay: 0.300) {
//        sendText(
//          """
//          id: 456
//          event: dlv
//          data: {"messageId":"2a3b4c", "occurredAt": 0, "sent": 10}
//
//
//          """
//        )
//      }
//
//      loop.call(withDelay: 0.450) {
//        sendText(
//          """
//          id: 789
//          event: dlv
//          data: {"messageId":"3a4b5c", "occurredAt": 0, "sent": 10}
//
//
//          """
//        )
//      }
//
//    }
//
//    server = DefaultHTTPServer(eventLoop: loop, interface: "::", port: 0, app: router.app)
//  }
//
//  func start() {
//
//    try! server.start()
//
//    DispatchQueue.global(qos: .background).async {
//      self.loop.runForever()
//    }
//
//  }
//
//  func stop() {
//    server.stopAndWait()
//    loop.stop()
//  }
//
//}
//
