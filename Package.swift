// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "combustion-ios-ble",
    platforms: [
        .iOS(.v13)
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-collections", "1.0.0"..<"2.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "CombustionBLE",
            dependencies: [
                .product(name: "Collections", package: "swift-collections", condition: nil)
            ],
            path: "Sources/CombustionBLE"),
        /*
        .testTarget(
            name: "combustion-ios-bleTests",
            dependencies: ["combustion-ios-ble"]),
        */
    ]
)
