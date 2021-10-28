// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "Sunday",
  platforms: [
    .iOS(.v13),
    .tvOS(.v13),
    .watchOS(.v6),
    .macOS(.v10_15)
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
    .package(url: "https://github.com/SwiftScream/URITemplate.git", from: "2.1.0")
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
        "SundayServer"
      ]
    ),
  ]
)
