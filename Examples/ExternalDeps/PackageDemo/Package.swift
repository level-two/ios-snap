// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PackageDemo",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PackageFeature",
            type: .dynamic,
            targets: ["PackageFeature"]
        )
    ],
    targets: [
        .target(
            name: "PackageFeature",
            swiftSettings: [
                .define("IOS_SNAP_EXAMPLE", .when(platforms: [.iOS]))
            ]
        )
    ]
)
