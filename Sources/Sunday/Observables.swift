//
//  Observables.swift
//  Sunday
//
//  Copyright © 2018 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import PromiseKit
import RxSwift


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

