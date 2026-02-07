// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "recent-work",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "RecentWork"
        ),
        .executableTarget(
            name: "recent-work",
            dependencies: [
                "RecentWork",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
