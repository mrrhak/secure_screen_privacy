// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "secure_screen_privacy",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "secure-screen-privacy", targets: ["secure_screen_privacy"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "secure_screen_privacy",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // Privacy manifest: declares ProcessInfo.systemUptime (screenshot dedupe).
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
