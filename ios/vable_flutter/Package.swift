// swift-tools-version: 5.9
import Foundation
import PackageDescription

// To try an unreleased Swift SDK, set VABLE_SWIFT_LOCAL to a vable-swift-sdk checkout and
// VABLE_LOCAL_BINARY=1, after running its scripts/build_xcframework.sh.
let localSDK = ProcessInfo.processInfo.environment["VABLE_SWIFT_LOCAL"]
let vableSDK: Package.Dependency =
    localSDK.map { .package(path: $0) }
    ?? .package(url: "https://github.com/vable-ai/vable-swift.git", from: "0.0.6")
let vableSDKName = localSDK.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "vable-swift"

let package = Package(
    name: "vable_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "vable-flutter", targets: ["vable_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        vableSDK,
    ],
    targets: [
        .target(
            name: "vable_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "VableAI", package: vableSDKName),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
