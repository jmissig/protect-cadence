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
            name: "protect-cadence-ingest",
            targets: ["protect-cadence-ingest"]
        ),
        .executable(
            name: "protect-cadence-query",
            targets: ["protect-cadence-query"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.8.0"),
    ],
    targets: [
        .target(
            name: "ProtectCadenceCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "protect-cadence-ingest",
            dependencies: ["ProtectCadenceCore"]
        ),
        .executableTarget(
            name: "protect-cadence-query",
            dependencies: ["ProtectCadenceCore"]
        ),
        .testTarget(
            name: "ProtectCadenceCoreTests",
            dependencies: ["ProtectCadenceCore"]
        ),
    ]
)
