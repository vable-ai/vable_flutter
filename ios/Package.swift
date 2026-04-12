// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vable_flutter",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "vable_flutter", targets: ["vable_flutter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vable-ai/vable-swift-sdk.git", revision: "fa1ac27"),
    ],
    targets: [
        .target(
            name: "vable_flutter",
            dependencies: [
                .product(name: "VableAI", package: "VableAI"),
            ],
            path: "Sources/vable_flutter"
        ),
    ]
)
