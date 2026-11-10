// swift-tools-version: 6.2
import Foundation
import PackageDescription

// HARBOR_STRICT=1 (Scripts/verify.sh, CI) turns every warning in Harbor's own targets
// into an error. Opt-in so a new Xcode's fresh deprecations can't break a dev build.
let strict = ProcessInfo.processInfo.environment["HARBOR_STRICT"] == "1"
let warnings: [SwiftSetting] = strict ? [.treatAllWarnings(as: .error)] : []

let package = Package(
    name: "Harbor",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // Harbor CLI tool for command-line access
        .executable(name: "harborcli", targets: ["HarborCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sriinnu/Silo.git", from: "1.0.0"),
        .package(url: "https://github.com/steipete/Commander", from: "0.2.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),
        .package(url: "https://github.com/openid/AppAuth-iOS", from: "2.0.0"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "8.8.0"),
    ],
    targets: [
        .target(
            name: "HarborCore",
            dependencies: [
                "Silo",
            ],
            exclude: [
                "DesignSystem/design-tokens.json", // design reference, not a runtime resource
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ] + warnings),
        .executableTarget(
            name: "Harbor",
            dependencies: [
                "HarborCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "AppAuth", package: "AppAuth-iOS"),
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            exclude: [
                "Resources/Info.plist", // reference only; Scripts/package_app.sh writes the shipped one
            ],
            resources: [
                .copy("Resources/Harbor.entitlements"),
                .copy("Resources/logo.png"),
                .copy("Resources/AppIcon.icns"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ] + warnings),
        .executableTarget(
            name: "HarborCLI",
            dependencies: [
                .product(name: "Commander", package: "Commander"),
                "HarborCore",
            ],
            path: "Sources/HarborCLI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ] + warnings),
        .testTarget(
            name: "HarborTests",
            dependencies: ["Harbor", "HarborCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ] + warnings),
        .testTarget(
            name: "HarborCoreTests",
            dependencies: ["HarborCore"],
            path: "Tests/HarborCoreTests",
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ] + warnings),
        .testTarget(
            name: "harborcliTests",
            dependencies: ["HarborCLI"],
            path: "Tests/HarborCLITests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ] + warnings),
    ])
