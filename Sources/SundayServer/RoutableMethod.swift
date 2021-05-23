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

//  swiftlint:disable function_parameter_count identifier_name

import Foundation
import Sunday


public struct Method: Routable {

  public let method: HTTP.Method
  public let handler: RouteHandler

  public init(method: HTTP.Method, handler: @escaping RouteHandler) {
    self.method = method
    self.handler = handler
  }

  public func route(_ route: Route, request: HTTPRequest) throws -> RouteResult? {
    guard route.unmatched.isEmpty, method == request.method else { return nil }
    return (route, handler)
  }

}


func convert<T>(_ param: Param<T>, _ route: Route, _ request: HTTPRequest, _ response: HTTPResponse) throws -> T {
  let converted: T?
  do {
    converted = try param.converter(route, request, response)
  }
  catch {
    throw RoutingError.parameterConversionFailed(name: param.name, error: error)
  }
  guard let value = converted else {
    throw RoutingError.missingRequiredParameter(name: param.name)
  }
  return value
}


func convert<T>(_ param: Param<T>, _ route: Route, request: HTTPRequest, _ response: HTTPResponse) throws -> T? {
  do {
    return try param.converter(route, request, response)
  }
  catch {
    throw RoutingError.parameterConversionFailed(name: param.name, error: error)
  }
}


public func METHOD(
  _ method: HTTP.Method,
  _ handler: @escaping (HTTPRequest, HTTPResponse) throws -> Void
) -> Routable {
  return Method(method: method) { _, request, response in
    try handler(request, response)
  }
}


public func METHOD<A1>(
  _ method: HTTP.Method,
  _ a1: Param<A1>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1) throws -> Void
) -> Routable {
  return Method(method: method) { route, request, response in
    try handler(
      request,
      response,
      try convert(a1, route, request, response)
    )
  }
}


public func METHOD<A1, A2>(
  _ method: HTTP.Method,
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2) throws -> Void
) -> Routable {
  return Method(method: method) { route, request, response in
    try handler(
      request,
      response,
      try convert(a1, route, request, response),
      try convert(a2, route, request, response)
    )
  }
}


public func METHOD<A1, A2, A3>(
  _ method: HTTP.Method,
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3) throws -> Void
) -> Routable {
  return Method(method: method) { route, request, response in
    try handler(
      request,
      response,
      try convert(a1, route, request, response),
      try convert(a2, route, request, response),
      try convert(a3, route, request, response)
    )
  }
}


public func METHOD<A1, A2, A3, A4>(
  _ method: HTTP.Method,
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4) throws -> Void
) -> Routable {
  return Method(method: method) { route, request, response in
    try handler(
      request,
      response,
      try convert(a1, route, request, response),
      try convert(a2, route, request, response),
      try convert(a3, route, request, response),
      try convert(a4, route, request, response)
    )
  }
}


public func METHOD<A1, A2, A3, A4, A5>(
  _ method: HTTP.Method,
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ a5: Param<A5>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4, A5) throws -> Void
) -> Routable {
  return Method(method: method) { route, request, response in
    try handler(
      request,
      response,
      try convert(a1, route, request, response),
      try convert(a2, route, request, response),
      try convert(a3, route, request, response),
      try convert(a4, route, request, response),
      try convert(a5, route, request, response)
    )
  }
}


public func GET(_ handler: @escaping (HTTPRequest, HTTPResponse) throws -> Void) -> Routable {
  return METHOD(.get, handler)
}

public func GET<A1>(
  _ a1: Param<A1>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1) throws -> Void
) -> Routable {
  return METHOD(.get, a1, handler)
}

public func GET<A1, A2>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2) throws -> Void
) -> Routable {
  return METHOD(.get, a1, a2, handler)
}

public func GET<A1, A2, A3>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3) throws -> Void
) -> Routable {
  return METHOD(.get, a1, a2, a3, handler)
}

public func GET<A1, A2, A3, A4>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4) throws -> Void
) -> Routable {
  return METHOD(.get, a1, a2, a3, a4, handler)
}

public func GET<A1, A2, A3, A4, A5>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ a5: Param<A5>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4, A5) throws -> Void
) -> Routable {
  return METHOD(.get, a1, a2, a3, a4, a5, handler)
}


public func PUT(_ handler: @escaping (HTTPRequest, HTTPResponse) throws -> Void) -> Routable {
  return METHOD(.put, handler)
}

public func PUT<A1>(
  _ a1: Param<A1>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1) throws -> Void
) -> Routable {
  return METHOD(.put, a1, handler)
}

public func PUT<A1, A2>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2) throws -> Void
) -> Routable {
  return METHOD(.put, a1, a2, handler)
}

public func PUT<A1, A2, A3>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3) throws -> Void
) -> Routable {
  return METHOD(.put, a1, a2, a3, handler)
}

public func PUT<A1, A2, A3, A4>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4) throws -> Void
) -> Routable {
  return METHOD(.put, a1, a2, a3, a4, handler)
}

public func PUT<A1, A2, A3, A4, A5>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ a5: Param<A5>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4, A5) throws -> Void
) -> Routable {
  return METHOD(.put, a1, a2, a3, a4, a5, handler)
}


public func POST(_ handler: @escaping (HTTPRequest, HTTPResponse) throws -> Void) -> Routable {
  return METHOD(.post, handler)
}

public func POST<A1>(
  _ a1: Param<A1>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1) throws -> Void
) -> Routable {
  return METHOD(.post, a1, handler)
}

public func POST<A1, A2>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2) throws -> Void
) -> Routable {
  return METHOD(.post, a1, a2, handler)
}

public func POST<A1, A2, A3>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3) throws -> Void
) -> Routable {
  return METHOD(.post, a1, a2, a3, handler)
}

public func POST<A1, A2, A3, A4>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4) throws -> Void
) -> Routable {
  return METHOD(.post, a1, a2, a3, a4, handler)
}

public func POST<A1, A2, A3, A4, A5>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ a5: Param<A5>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4, A5) throws -> Void
) -> Routable {
  return METHOD(.post, a1, a2, a3, a4, a5, handler)
}


public func DELETE(_ handler: @escaping (HTTPRequest, HTTPResponse) throws -> Void) -> Routable {
  return METHOD(.delete, handler)
}

public func DELETE<A1>(
  _ a1: Param<A1>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1) throws -> Void
) -> Routable {
  return METHOD(.delete, a1, handler)
}

public func DELETE<A1, A2>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2) throws -> Void
) -> Routable {
  return METHOD(.delete, a1, a2, handler)
}

public func DELETE<A1, A2, A3>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3) throws -> Void
) -> Routable {
  return METHOD(.delete, a1, a2, a3, handler)
}

public func DELETE<A1, A2, A3, A4>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4) throws -> Void
) -> Routable {
  return METHOD(.delete, a1, a2, a3, a4, handler)
}

public func DELETE<A1, A2, A3, A4, A5>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ a5: Param<A5>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4, A5) throws -> Void
) -> Routable {
  return METHOD(.delete, a1, a2, a3, a4, a5, handler)
}


public func HEAD(_ handler: @escaping (HTTPRequest, HTTPResponse) throws -> Void) -> Routable {
  return METHOD(.head, handler)
}

public func HEAD<A1>(
  _ a1: Param<A1>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1) throws -> Void
) -> Routable {
  return METHOD(.head, a1, handler)
}

public func HEAD<A1, A2>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2) throws -> Void
) -> Routable {
  return METHOD(.head, a1, a2, handler)
}

public func HEAD<A1, A2, A3>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3) throws -> Void
) -> Routable {
  return METHOD(.head, a1, a2, a3, handler)
}

public func HEAD<A1, A2, A3, A4>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4) throws -> Void
) -> Routable {
  return METHOD(.head, a1, a2, a3, a4, handler)
}

public func HEAD<A1, A2, A3, A4, A5>(
  _ a1: Param<A1>,
  _ a2: Param<A2>,
  _ a3: Param<A3>,
  _ a4: Param<A4>,
  _ a5: Param<A5>,
  _ handler: @escaping (HTTPRequest, HTTPResponse, A1, A2, A3, A4, A5) throws -> Void
) -> Routable {
  return METHOD(.head, a1, a2, a3, a4, a5, handler)
}
