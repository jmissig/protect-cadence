// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ProtectCadence",
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
    targets: [
        .target(
            name: "ProtectCadenceCore"
        ),
        .executableTarget(
            name: "protect-cadence-ingest",
            dependencies: ["ProtectCadenceCore"]
        ),
        .executableTarget(
            name: "protect-cadence-query",
            dependencies: ["ProtectCadenceCore"]
        ),
    ]
)
