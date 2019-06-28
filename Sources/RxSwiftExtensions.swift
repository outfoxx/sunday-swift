//
//  RxSwiftExtensions.swift
//  Sunday
//
//  Created by Kevin Wooten on 7/17/18.
//  Copyright © 2018 Outfox, Inc. All rights reserved.
//

import RxSwift
import PromiseKit


extension PrimitiveSequence where Trait == SingleTrait {

  public func promise() -> Promise<Element> {
    let (promise, resolver) = Promise.pending() as (Promise<Element>, Resolver<Element>)
    let disposer = subscribe(
      onSuccess: { element in
        resolver.fulfill(element)
      },
      onError: { error in
        resolver.reject(error)
      }
    )
    return promise.ensure {
      disposer.dispose()
    }
  }

}


extension PrimitiveSequence where Trait == CompletableTrait, Element == Swift.Never {

  public func promise() -> Promise<Void> {
    let (promise, resolver) = Promise.pending() as (Promise<Void>, Resolver<Void>)
    let disposer = subscribe(
      onCompleted: {
        resolver.fulfill(())
      },
      onError: { error in
        resolver.reject(error)
      }
    )
    return promise.ensure {
      disposer.dispose()
    }
  }

}
