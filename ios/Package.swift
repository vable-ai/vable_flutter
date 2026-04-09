// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ios",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ios",
            targets: ["ios"]
        ),
    ],
    platforms: [
        .iOS("13.0"),
    ],
    dependencies: [
        .package(path: "/Users/jamesfalade/workspace/vable-swift-sdk")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ios",
            dependencies: [
                .product(name: "VableSwiftSDK", package: "vable-swift-sdk")
            ]
        ),
        .testTarget(
            name: "iosTests",
            dependencies: ["ios"]
        ),
    ]
)
