// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "Sunday",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .watchOS(.v6),
    .tvOS(.v13)
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
    .package(url: "https://github.com/outfoxx/PotentCodables.git", from: "2.0.0"),
    .package(url: "https://github.com/outfoxx/OSLogTrace.git", from: "1.1.1"),
    .package(url: "https://github.com/sharplet/Regex.git", from: "2.1.0"),
    .package(url: "https://github.com/SwiftScream/URITemplate.git", from: "2.1.0"),
    .package(url: "https://github.com/groue/CombineExpectations.git", from: "0.7.0")
  ],
  targets: [
    .target(
      name: "Sunday",
      dependencies: [
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
        "CombineExpectations"
      ]
    ),
  ]
)
