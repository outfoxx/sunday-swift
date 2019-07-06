//
//  Logging.swift
//
//
//  Created by Kevin Wooten on 7/5/19.
//

import Foundation
import OSLogTrace


internal let logging = OSLogManager.for(subsystem: Bundle.target.bundleIdentifier!)
