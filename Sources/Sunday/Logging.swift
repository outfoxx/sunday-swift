//
//  Logging.swift
//  Sunday
//
//  Created by Kevin Wooten on 6/20/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import Foundation
import OSLogTrace


internal let logging = OSLogManager.for(subsystem: Bundle.target.bundleIdentifier!)
