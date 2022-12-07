// swift-tools-version:5.4

import PackageDescription

let package = Package(
  name: "Sunday",
  platforms: [
    .iOS(.v14),
    .tvOS(.v14),
    .watchOS(.v7),
    .macOS(.v11)
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
    .package(url: "https://github.com/outfoxx/PotentCodables.git", .upToNextMinor(from: "2.3.0")),
    .package(url: "https://github.com/sharplet/Regex.git", .upToNextMinor(from: "2.1.0")),
    .package(url: "https://github.com/SwiftScream/URITemplate.git", .upToNextMinor(from: "2.1.0"))
  ],
  targets: [
    .target(
      name: "Sunday",
      dependencies: [
        "Regex",
        "PotentCodables",
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

#if swift(>=5.6)
  // Add the documentation compiler plugin if possible
  package.dependencies.append(
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
  )
#endif
