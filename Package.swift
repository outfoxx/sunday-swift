// swift-tools-version:6.2

import PackageDescription

let package = Package(
  name: "Sunday",
  platforms: [
    .iOS(.v18),
    .tvOS(.v18),
    .watchOS(.v11),
    .macOS(.v15)
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
    .package(url: "https://github.com/openid/AppAuth-iOS.git", exact: "3.0.0"),
    .package(url: "https://github.com/outfoxx/PotentCodables.git", .upToNextMinor(from: "3.5.3")),
    .package(url: "https://github.com/sharplet/Regex.git", .upToNextMinor(from: "2.1.0")),
    .package(url: "https://github.com/SwiftScream/URITemplate.git", .upToNextMinor(from: "4.0.0"))
  ],
  targets: [
    .target(
      name: "Sunday",
      dependencies: [
        .product(name: "AppAuthCore", package: "AppAuth-iOS"),
        "Regex",
        "PotentCodables",
        .product(name: "ScreamURITemplate", package: "uritemplate")
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
      ],
      resources: [.copy("Resources/oauth-cases.json"), .copy("Resources/oauth-http-cases.json"), .copy("Resources/oauth-browser")]
    ),
  ]
)

#if swift(>=5.6)
  // Add the documentation compiler plugin if possible
  package.dependencies.append(
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0")
  )
#endif
