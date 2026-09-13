// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LGLanScanner",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LGLanScanner", targets: ["LGLanScanner"]),
    ],
    // No dependencies: Swift Concurrency over unprivileged ICMP sockets, plus two routing-table
    // reads in C (the iOS SDK does not ship <net/route.h>).
    targets: [
        .target(
            name: "LGLanScanner",
            dependencies: ["LanScanInternal"],
            resources: [.process("Resources")]
        ),
        .target(name: "LanScanInternal"),
        .testTarget(name: "LGLanScannerTests", dependencies: ["LGLanScanner"]),
    ]
)
