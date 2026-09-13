// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LGLanScanner",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LGLanScanner", targets: ["LGLanScanner"]),
        .library(name: "LGLanDiscovery", targets: ["LGLanDiscovery"]),
    ],
    // No dependencies. LGLanScanner: Swift Concurrency over unprivileged ICMP sockets, plus two
    // routing-table reads in C (the iOS SDK does not ship <net/route.h>). LGLanDiscovery: Bonjour
    // (NWBrowser) and SSDP (NWConnectionGroup) service discovery.
    targets: [
        .target(
            name: "LGLanScanner",
            dependencies: ["LanScanInternal"],
            resources: [.process("Resources")]
        ),
        .target(name: "LanScanInternal"),
        .testTarget(name: "LGLanScannerTests", dependencies: ["LGLanScanner"]),
        .target(name: "LGLanDiscovery"),
        .testTarget(name: "LGLanDiscoveryTests", dependencies: ["LGLanDiscovery"]),
    ]
)
