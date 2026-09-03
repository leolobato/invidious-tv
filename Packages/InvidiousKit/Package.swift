// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InvidiousKit",
    platforms: [.tvOS(.v18), .iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "InvidiousKit", targets: ["InvidiousKit"]),
    ],
    targets: [
        .target(
            name: "InvidiousKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "InvidiousKitTests",
            dependencies: ["InvidiousKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
