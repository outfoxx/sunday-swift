//
//  RoutableParam.swift
//  
//
//  Created by Kevin Wooten on 6/28/19.
//

import Foundation
import Sunday


public protocol StringInitializable {
  init?(_ source: String)
}


public struct Param<T> {

  public typealias Converter = ([String: Any], URLComponents, Data?) -> T?

  public let name: String
  public let converter: Converter

  public static func path(_ name: String) -> Param<String> {
    return path(name, String.self)
  }

  public static func path<U>(_ name: String, _ type: U.Type) -> Param<U> where U : StringInitializable {
    return Param<U>(name: name) { variables, _, _ in
      guard let value = variables[name] else { return nil }
      return U(String(describing: value))
    }
  }

  public static func query(_ name: String) -> Param<String> {
    return query(name, String.self)
  }

  public static func query<U>(_ name: String, _ type: U.Type) -> Param<U> where U : StringInitializable {
    return Param<U>(name: name) { _, url, _ in
      guard let value = url.queryItems?.filter({ $0.name == name }).first?.value else { return nil }
      return U(value)
    }
  }

  public static func query<U>(_ name: String, _ type: Array<U>.Type) -> Param<[U]> where U : StringInitializable {
    return Param<[U]>(name: name) { _, url, _ in
      guard let values = url.queryItems?.filter({ $0.name == name }).compactMap({ $0.value }) else { return nil }
      return values.compactMap { U($0) }
    }
  }

  public static func fragment(_ name: String) -> Param<String> {
    return fragment(name, String.self)
  }

  public static func fragment<U>(_ name: String, _ type: U.Type) -> Param<U> where U : StringInitializable {
    return Param<U>(name: name) { _, url, _ in
      guard let value = url.fragment else { return nil }
      return U(value)
    }
  }

  public static func body() -> Param<Data> {
    return body(Data.self)
  }

  public static func body<T>(_ type: T.Type) -> Param<T> where T : Decodable {
    return Param<T>(name: "@body") { variables, _, body in
      guard let decoder = variables["@body-decoder"] as? MediaTypeDecoder else { return nil }
      guard let body = body else { return nil }
      return try? decoder.decode(type, from: body)
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
