// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // Harbor CLI tool for command-line access
        .executable(name: "harbor", targets: ["harbor"]),
    ],
    dependencies: [
        .package(path: "../Packages/Silo"),
        .package(url: "https://github.com/steipete/Commander", from: "0.2.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", exact: "1.2.2"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),
        .package(url: "https://github.com/openid/AppAuth-iOS", from: "2.0.0"),
        .package(url: "https://github.com/apollographql/apollo-ios", from: "2.0.3"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "8.6.0"),
    ],
    targets: [
        .target(
            name: "HarborCore",
            dependencies: [
                "Silo",
                .product(name: "Apollo", package: "apollo-ios"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "Harbor",
            dependencies: [
                "HarborCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "AppAuth", package: "AppAuth-iOS"),
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/Assets.xcassets"),
                .copy("Resources/Harbor.entitlements"),
                .copy("Resources/logo.svg"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "harbor",
            dependencies: [
                .product(name: "Commander", package: "Commander"),
                "HarborCore",
            ],
            path: "Sources/HarborCLI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .testTarget(
            name: "HarborTests",
            dependencies: ["Harbor", "HarborCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
        .testTarget(
            name: "HarborCoreTests",
            dependencies: ["HarborCore"],
            path: "Tests/HarborCoreTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
        .testTarget(
            name: "harborcliTests",
            dependencies: ["harbor"],
            path: "Tests/HarborCLITests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
    ])
