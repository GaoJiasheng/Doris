// swift-tools-version: 5.10
import PackageDescription
import Foundation

// See DorisCore/Package.swift for the rationale — we remap source
// paths in debug info / __cstring so "khan" (in the worktree path)
// doesn't leak into the shipped binary.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let prefixMapFlags: [SwiftSetting] = [
    .unsafeFlags(["-Xfrontend", "-debug-prefix-map",
                  "-Xfrontend", "\(packageRoot)=/doris/packages/DorisUI"]),
    .unsafeFlags(["-Xfrontend", "-file-prefix-map",
                  "-Xfrontend", "\(packageRoot)=/doris/packages/DorisUI"])
]

let package = Package(
    name: "DorisUI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "DorisUI", targets: ["DorisUI"])
    ],
    dependencies: [
        .package(path: "../DorisCore")
    ],
    targets: [
        .target(
            name: "DorisUI",
            dependencies: [
                .product(name: "DorisCore", package: "DorisCore")
            ],
            path: "Sources/DorisUI",
            resources: [
                .copy("HeroAnim"),
                .copy("Characters")
            ],
            swiftSettings: prefixMapFlags
        )
    ]
)
