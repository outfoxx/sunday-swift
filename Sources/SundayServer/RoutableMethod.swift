//
//  RoutableMethod.swift
//  
//
//  Created by Kevin Wooten on 6/28/19.
//

import Foundation
import Sunday


public struct Method : Routable {

  public let method: HTTP.Method
  public let handler: ([String: Any], URLComponents, HTTP.Request) throws -> HTTP.Response

  public init(method: HTTP.Method, handler: @escaping ([String: Any], URLComponents, HTTP.Request) throws -> HTTP.Response) {
    self.method = method
    self.handler = handler
  }

  public func route(request: HTTP.Request, path: String, variables: [String: Any]) throws -> HTTP.Response? {
    guard path.isEmpty && method == request.method else { return nil }
    guard let url = URLComponents(url: request.url, resolvingAgainstBaseURL: true) else {
      throw RoutingError.invalidURL
    }
    return try handler(variables, url, request)
  }

}

public func METHOD(_ method: HTTP.Method,
                   _ handler: @escaping () throws -> HTTP.Response) -> Routable {
  return Method(method: method) { _, _, _ in
    return try handler()
  }
}


func convert<T>(_ param: Param<T>, _ variables: [String: Any], _ url: URLComponents, _ body: Data?) throws -> T {
  let converted: T?
  do {
     converted = try param.converter(variables, url, body)
  }
  catch {
    throw RoutingError.parameterConversionFailed(name: param.name, error: error)
  }
  guard let value = converted else {
    throw RoutingError.missingRequiredParameter(name: param.name)
  }
  return value
}

func convert<T>(_ param: Param<T>, _ variables: [String: Any], _ url: URLComponents, _ body: Data?) throws -> T? {
  do {
    return try param.converter(variables, url, body)
  }
  catch {
    throw RoutingError.parameterConversionFailed(name: param.name, error: error)
  }
}


public func METHOD<A1>(_ method: HTTP.Method,
                       _ a1: Param<A1>,
                       _ handler: @escaping (A1) throws -> HTTP.Response) -> Routable {
  return Method(method: method) { variables, url, request in
    let a1: A1 = try convert(a1, variables, url, request.body)
    return try handler(a1)
  }
}


public func METHOD<A1, A2>(_ method: HTTP.Method,
                           _ a1: Param<A1>, _ a2: Param<A2>,
                           _ handler: @escaping (A1, A2) throws -> HTTP.Response) -> Routable {
  return Method(method: method) { variables, url, request in
    return try handler(try convert(a1, variables, url, request.body),
                       try convert(a2, variables, url, request.body))
  }
}


public func METHOD<A1, A2, A3>(_ method: HTTP.Method,
                               _ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>,
                               _ handler: @escaping (A1, A2, A3) throws -> HTTP.Response) -> Routable {
  return Method(method: method) { variables, url, request in
    return try handler(try convert(a1, variables, url, request.body),
                       try convert(a2, variables, url, request.body),
                       try convert(a3, variables, url, request.body))
  }
}


public func METHOD<A1, A2, A3, A4>(_ method: HTTP.Method,
                                   _ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>,
                                   _ handler: @escaping (A1, A2, A3, A4) throws -> HTTP.Response) -> Routable {
  return Method(method: method) { variables, url, request in
    return try handler(try convert(a1, variables, url, request.body),
                       try convert(a2, variables, url, request.body),
                       try convert(a3, variables, url, request.body),
                       try convert(a4, variables, url, request.body))
  }
}


public func METHOD<A1, A2, A3, A4, A5>(_ method: HTTP.Method,
                                       _ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>, _ a5: Param<A5>,
                                       _ handler: @escaping (A1, A2, A3, A4, A5) throws -> HTTP.Response) -> Routable {
  return Method(method: method) { variables, url, request in
    return try handler(try convert(a1, variables, url, request.body),
                       try convert(a2, variables, url, request.body),
                       try convert(a3, variables, url, request.body),
                       try convert(a4, variables, url, request.body),
                       try convert(a5, variables, url, request.body))
  }
}


public func GET(_ handler: @escaping () throws -> HTTP.Response) -> Routable {
  return METHOD(.get, handler)
}

public func GET<A1>(_ a1: Param<A1>,
                    _ handler: @escaping (A1) throws -> HTTP.Response) -> Routable {
  return METHOD(.get, a1, handler)
}

public func GET<A1, A2>(_ a1: Param<A1>, _ a2: Param<A2>,
                        _ handler: @escaping (A1, A2) throws -> HTTP.Response) -> Routable {
  return METHOD(.get, a1, a2, handler)
}

public func GET<A1, A2, A3>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>,
                            _ handler: @escaping (A1, A2, A3) throws -> HTTP.Response) -> Routable {
  return METHOD(.get, a1, a2, a3, handler)
}

public func GET<A1, A2, A3, A4>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>,
                                _ handler: @escaping (A1, A2, A3, A4) throws -> HTTP.Response) -> Routable {
  return METHOD(.get, a1, a2, a3, a4, handler)
}

public func GET<A1, A2, A3, A4, A5>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>, _ a5: Param<A5>,
                                    _ handler: @escaping (A1, A2, A3, A4, A5) throws -> HTTP.Response) -> Routable {
  return METHOD(.get, a1, a2, a3, a4, a5, handler)
}


public func PUT(_ handler: @escaping () throws -> HTTP.Response) -> Routable {
  return METHOD(.put, handler)
}

public func PUT<A1>(_ a1: Param<A1>,
                    _ handler: @escaping (A1) throws -> HTTP.Response) -> Routable {
  return METHOD(.put, a1, handler)
}

public func PUT<A1, A2>(_ a1: Param<A1>, _ a2: Param<A2>,
                        _ handler: @escaping (A1, A2) throws -> HTTP.Response) -> Routable {
  return METHOD(.put, a1, a2, handler)
}

public func PUT<A1, A2, A3>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>,
                            _ handler: @escaping (A1, A2, A3) throws -> HTTP.Response) -> Routable {
  return METHOD(.put, a1, a2, a3, handler)
}

public func PUT<A1, A2, A3, A4>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>,
                                _ handler: @escaping (A1, A2, A3, A4) throws -> HTTP.Response) -> Routable {
  return METHOD(.put, a1, a2, a3, a4, handler)
}

public func PUT<A1, A2, A3, A4, A5>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>, _ a5: Param<A5>,
                                    _ handler: @escaping (A1, A2, A3, A4, A5) throws -> HTTP.Response) -> Routable {
  return METHOD(.put, a1, a2, a3, a4, a5, handler)
}


public func POST(_ handler: @escaping () throws -> HTTP.Response) -> Routable {
  return METHOD(.post, handler)
}

public func POST<A1>(_ a1: Param<A1>,
                     _ handler: @escaping (A1) throws -> HTTP.Response) -> Routable {
  return METHOD(.post, a1, handler)
}

public func POST<A1, A2>(_ a1: Param<A1>, _ a2: Param<A2>,
                         _ handler: @escaping (A1, A2) throws -> HTTP.Response) -> Routable {
  return METHOD(.post, a1, a2, handler)
}

public func POST<A1, A2, A3>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>,
                             _ handler: @escaping (A1, A2, A3) throws -> HTTP.Response) -> Routable {
  return METHOD(.post, a1, a2, a3, handler)
}

public func POST<A1, A2, A3, A4>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>,
                                 _ handler: @escaping (A1, A2, A3, A4) throws -> HTTP.Response) -> Routable {
  return METHOD(.post, a1, a2, a3, a4, handler)
}

public func POST<A1, A2, A3, A4, A5>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>, _ a5: Param<A5>,
                                     _ handler: @escaping (A1, A2, A3, A4, A5) throws -> HTTP.Response) -> Routable {
  return METHOD(.post, a1, a2, a3, a4, a5, handler)
}


public func DELETE(_ handler: @escaping () throws -> HTTP.Response) -> Routable {
  return METHOD(.delete, handler)
}

public func DELETE<A1>(_ a1: Param<A1>,
                       _ handler: @escaping (A1) throws -> HTTP.Response) -> Routable {
  return METHOD(.delete, a1, handler)
}

public func DELETE<A1, A2>(_ a1: Param<A1>, _ a2: Param<A2>,
                           _ handler: @escaping (A1, A2) throws -> HTTP.Response) -> Routable {
  return METHOD(.delete, a1, a2, handler)
}

public func DELETE<A1, A2, A3>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>,
                               _ handler: @escaping (A1, A2, A3) throws -> HTTP.Response) -> Routable {
  return METHOD(.delete, a1, a2, a3, handler)
}

public func DELETE<A1, A2, A3, A4>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>,
                                   _ handler: @escaping (A1, A2, A3, A4) throws -> HTTP.Response) -> Routable {
  return METHOD(.delete, a1, a2, a3, a4, handler)
}

public func DELETE<A1, A2, A3, A4, A5>(_ a1: Param<A1>, _ a2: Param<A2>, _ a3: Param<A3>, _ a4: Param<A4>, _ a5: Param<A5>,
                                       _ handler: @escaping (A1, A2, A3, A4, A5) throws -> HTTP.Response) -> Routable {
  return METHOD(.delete, a1, a2, a3, a4, a5, handler)
}
