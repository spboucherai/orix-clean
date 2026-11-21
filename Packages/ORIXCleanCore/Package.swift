// swift-tools-version: 6.0
// ORIX Clean — Packages/ORIXCleanCore/Package.swift
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import PackageDescription

let package = Package(
    name: "ORIXCleanCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ORIXCleanCore", targets: ["ORIXCleanCore"]),
        .executable(name: "orix-bench", targets: ["orix-bench"]),
    ],
    targets: [
        .target(name: "ORIXCleanCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "orix-bench", dependencies: ["ORIXCleanCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ORIXCleanCoreTests", dependencies: ["ORIXCleanCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
