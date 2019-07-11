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
    .library(
      name: "SundayServer",
      targets: ["SundayServer"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/outfoxx/PotentCodables.git", from: "1.1.0"),
    .package(url: "https://github.com/outfoxx/OSLogTrace.git", from: "1.0.0"),
    .package(url: "https://github.com/Alamofire/Alamofire.git", from: "4.8.2"),
    .package(url: "https://github.com/mxcl/PromiseKit.git", from: "6.10.0"),
    .package(url: "https://github.com/PromiseKit/Foundation.git", from: "3.3.3"),
    .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "5.0.0"),
    .package(url: "https://github.com/sharplet/Regex.git", from: "2.1.0"),
    .package(url: "https://github.com/SwiftScream/URITemplate.git", from: "2.1.0"),
  ],
  targets: [
    .target(
      name: "Sunday",
      dependencies: [
        "Alamofire",
        "PromiseKit",
        "PMKFoundation",
        "RxSwift",
        "Regex",
        "PotentCodables",
        "OSLogTrace",
        "URITemplate"
      ]
    ),
    .target(
      name: "SundayServer",
      dependencies: [
        "Sunday",
      ]
    ),
    .testTarget(
      name: "SundayTests",
      dependencies: [
        "Sunday",
        "SundayServer",
      ]
    ),
  ]
)
