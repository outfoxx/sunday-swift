//
//  ModuleBundle.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/20/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation


@objc private class BundleLocator : NSObject {}

extension Bundle {

  internal class var framework: Bundle {
    return Bundle(for: BundleLocator.self)
  }

}
