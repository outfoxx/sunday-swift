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
    .package(url: "https://github.com/outfoxx/PotentCodables.git", from: "1.7.1"),
    .package(url: "https://github.com/outfoxx/OSLogTrace.git", from: "1.1.1"),
    .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "5.0.0"),
    .package(url: "https://github.com/sharplet/Regex.git", from: "2.1.0"),
    .package(url: "https://github.com/SwiftScream/URITemplate.git", from: "2.1.0")
  ],
  targets: [
    .target(
      name: "Sunday",
      dependencies: [
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
        "Sunday"
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
