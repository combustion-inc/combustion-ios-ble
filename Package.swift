// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "combustion-ios-ble",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(name: "CombustionBLE", targets: ["CombustionBLE"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-collections", "1.0.0"..<"2.0.0"),
        .package(url: "https://github.com/NordicSemiconductor/IOS-DFU-Library", .upToNextMajor(from: "4.11.1"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "CombustionBLE",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "NordicDFU", package: "IOS-DFU-Library")
            ],
            path: "Sources/CombustionBLE"),
        /*
        .testTarget(
            name: "combustion-ios-bleTests",
            dependencies: ["combustion-ios-ble"]),
        */
    ]
)
