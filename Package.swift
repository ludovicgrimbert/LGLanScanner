// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LGLanScanner",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "LGLanScanner",
            targets: ["LGLanScanner"]),
    ],
    // No dependencies: the scanner is plain Swift Concurrency on top of the Objective-C
    // LanScanInternal target.
    targets: [
        .target(
            name: "LGLanScanner",
            dependencies: ["LanScanInternal"]
        ),
        .target(
            name: "LanScanInternal",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
