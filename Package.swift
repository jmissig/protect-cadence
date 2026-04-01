// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ProtectCadence",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ProtectCadenceCore",
            targets: ["ProtectCadenceCore"]
        ),
        .executable(
            name: "protect-cadence",
            targets: ["protect-cadence"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.8.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ProtectCadenceCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "protect-cadence",
            dependencies: ["ProtectCadenceCore"]
        ),
        .testTarget(
            name: "ProtectCadenceCoreTests",
            dependencies: ["ProtectCadenceCore"]
        ),
    ]
)
