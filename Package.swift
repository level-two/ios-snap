// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ios-snap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ios-snap", targets: ["ios-snap"]),
        .library(name: "SnapshotKit", targets: ["SnapshotKit"]),
        .plugin(name: "IOSSnapPlugin", targets: ["IOSSnapPlugin"])
    ],
    dependencies: [
        // CLI parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        // YAML parsing (to be used in Phase H)
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.2")
    ],
    targets: [
        .executableTarget(
            name: "ios-snap",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/ios-snap"
        ),
        .target(
            name: "SnapshotKit",
            dependencies: [],
            path: "Sources/SnapshotKit"
        ),
        .plugin(
            name: "IOSSnapPlugin",
            capability: .command(
                intent: .custom(
                    verb: "ios-snap",
                    description: "Run ios-snap CLI commands from swift package"
                )
            ),
            dependencies: [
                .target(name: "ios-snap")
            ]
        )
    ]
)
