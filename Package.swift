// swift-tools-version:5.1

import PackageDescription

let package = Package(
  name: "Sunday",
  platforms: [
    .iOS(.v10),
    .macOS(.v10_12),
    .watchOS(.v3),
    .tvOS(.v10)
  ],
  products: [
    .library(
      name: "Sunday",
      targets: ["Sunday"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/outfoxx/OSLogTrace.git", from: "1.0.0"),
    .package(url: "https://github.com/outfoxx/PotentCodables.git", from: "1.0.0"),
    .package(url: "https://github.com/Alamofire/Alamofire.git", from: "4.8.0"),
    .package(url: "https://github.com/mxcl/PromiseKit.git", from: "7.0.0-alpha1"),
    .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "5.0.0"),
    .package(url: "https://github.com/sharplet/Regex.git", from: "2.1.0"),
    .package(url: "https://github.com/outfoxx/Embassy.git", from: "4.1.1"),
    .package(url: "https://github.com/envoy/Ambassador.git", from: "4.0.5")
  ],
  targets: [
    .target(
      name: "Sunday",
      dependencies: [
        "Alamofire",
        "PromiseKit",
        "RxSwift",
        "Regex",
        "PotentCodables",
        "OSLogTrace"
      ],
      path: "Sources"
    ),
    .testTarget(
      name: "SundayTests",
      dependencies: [
        "Sunday",
        "Embassy",
        "Ambassador"
      ],
      path: "Tests"
    ),
  ]
)
