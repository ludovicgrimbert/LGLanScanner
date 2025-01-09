// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LGLanScanner",
    platforms: [.iOS(.v17)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "LGLanScanner",
            targets: ["LGLanScanner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "LGLanScanner",
            dependencies: ["LanScanInternal",
                           .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
                          ]
        ),
        .target(
            name: "LanScanInternal",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
//        .testTarget(
//            name: "LanScannerTests",
//            dependencies: []),
    ]
)
