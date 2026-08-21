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
        .package(path: "../DorisCore"),
        .package(path: "../DorisCharacters")
    ],
    targets: [
        .target(
            name: "DorisUI",
            dependencies: [
                .product(name: "DorisCore", package: "DorisCore"),
                // macOS only. The character art is ~254 MB of frame-by-frame
                // PNG that only `#if os(macOS)` code ever reads; when it was
                // declared as a resource of THIS target, SwiftPM copied it
                // into the iOS app and again into the widget extension —
                // half a gigabyte of assets iOS never draws. A conditional
                // dependency keeps it off that platform entirely.
                .product(name: "DorisCharacters", package: "DorisCharacters",
                         condition: .when(platforms: [.macOS]))
            ],
            path: "Sources/DorisUI",
            swiftSettings: prefixMapFlags
        )
    ]
)
