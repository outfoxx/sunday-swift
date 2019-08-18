//
//  RoutableParam.swift
//  
//
//  Created by Kevin Wooten on 6/28/19.
//

import Foundation
import Sunday
import PotentCodables


public protocol StringInitializable {
  init?(_ source: String)
}


public struct Param<T> {

  public typealias Converter = (Route, HTTPRequest, HTTPResponse) throws -> T?

  public let name: String
  public let converter: Converter

  public static func prop( _ name: String) -> Param<Any> {
    return Param<Any>(name: name) { route, req, res in
      guard let value = res.properties[name] else { return nil }
      return value
    }
  }

  public static func prop<U>( _ name: String, _ type: U.Type) -> Param<U> {
    return Param<U>(name: name) { route, req, res in
      guard let value = res.properties[name] as? U else { return nil }
      return value
    }
  }

  public static func path(_ name: String) -> Param<String> {
    return path(name, String.self)
  }

  public static func path<U>(_ name: String, _ type: U.Type) -> Param<U> where U : StringInitializable {
    return Param<U>(name: name) { route, req, res in
      guard let value = route.parameters[name] else { return nil }
      return U(String(describing: value))
    }
  }

  public static func query(_ name: String) -> Param<String> {
    return query(name, String.self)
  }

  public static func query<U>(_ name: String, _ type: U.Type) -> Param<U> where U : StringInitializable {
    return Param<U>(name: name) { route, req, res in
      guard let value = req.url.queryItems?.filter({ $0.name == name }).first?.value else { return nil }
      return U(value)
    }
  }

  public static func query<U>(_ name: String, _ type: Array<U>.Type) -> Param<[U]> where U : StringInitializable {
    return Param<[U]>(name: name) { route, req, res in
      guard let values = req.url.queryItems?.filter({ $0.name == name }).compactMap({ $0.value }) else { return nil }
      return values.compactMap { U($0) }
    }
  }

  public static func fragment(_ name: String) -> Param<String> {
    return fragment(name, String.self)
  }

  public static func fragment<U>(_ name: String, _ type: U.Type) -> Param<U> where U : StringInitializable {
    return Param<U>(name: name) { route, req, res in
      guard let value = req.url.fragment else { return nil }
      return U(value)
    }
  }

  public static func body() -> Param<Data> {
    return body(Data.self)
  }

  public static func body<T>(_ type: T.Type) -> Param<T> where T : Decodable {
    return Param<T>(name: "@body") { route, req, res in
      guard let decoder = res.properties["@body-decoder"] as? MediaTypeDecoder else { return nil }
      guard let body = req.body else { return nil }
      return try decoder.decode(type, from: body)
    }
  }

  public static func body<T>(ref: T.Type) -> Param<T> {
    return Param<T>(name: "@body") { route, req, res in
      guard let decoder = res.properties["@body-decoder"] as? MediaTypeDecoder else { return nil }
      guard let body = req.body else { return nil }
      return try decoder.decode(Ref.self, from: body).as(T.self)
    }
  }

  public static func body<T>(embebbedRef: T.Type) -> Param<T> {
    return Param<T>(name: "@body") { route, req, res in
      guard let decoder = res.properties["@body-decoder"] as? MediaTypeDecoder else { return nil }
      guard let body = req.body else { return nil }
      return try decoder.decode(EmbeddedRef.self, from: body).as(T.self)
    }
  }

}

extension Bool : StringInitializable {}

extension Int : StringInitializable {}

extension Float : StringInitializable {}

extension String : StringInitializable {}

extension UUID : StringInitializable {
  @inlinable public init?(_ source: String) {
    self.init(uuidString: source)
  }
}
