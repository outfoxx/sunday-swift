//
//  PathParameters.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/18/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation
import Alamofire


public struct PathParameters {


  public enum Error : Swift.Error {
    case missingParameterValue
    case unsupportedParameterType
  }


  private static let pattern = try! NSRegularExpression(pattern: "\\{([a-zA-Z0-9_]+)\\}", options: [])

  public static func encode(_ path: String, with parameters: Parameters) throws -> String {

    let finalPath = NSMutableString(string: path)
    var offset = 0
    var foundError: Swift.Error? = nil

    PathParameters.pattern.enumerateMatches(in: path, options: [], range: NSRange(location: 0, length: path.count)) { result, _, stop in

      do {

        let result = result!

        let paramRange = result.range(at: 1)

        let param = String(path[Range(paramRange, in: path)!])

        let replacement: String?

        switch parameters[param] {
        case let value as PathParameterConvertible:
          replacement = value.path()
        case let value as CustomStringConvertible:
          replacement = value.description
        case nil:
          throw Error.missingParameterValue
        default:
          throw Error.unsupportedParameterType
        }

        if let replacement = replacement {

          let escapedResplacement = URLEncoding.default.escape(replacement)

          var range = result.range(at: 0)
          range.location += offset
          
          finalPath.replaceCharacters(in: range, with: escapedResplacement)
          offset += replacement.count - range.length
        }

      }
      catch {
        foundError = error
        stop.pointee = true
      }

    }

    if let foundError = foundError {
      throw foundError
    }

    return finalPath as String
  }

}
