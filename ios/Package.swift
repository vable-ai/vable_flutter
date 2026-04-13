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
        .package(url: "https://github.com/vable-ai/vable-swift.git", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "vable_flutter",
            dependencies: [
                .product(name: "VableAI", package: "vable-swift"),
            ],
            path: "Sources/vable_flutter"
        ),
    ]
)
