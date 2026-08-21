// swift-tools-version: 5.10
import PackageDescription

// The character art — three packs of frame-by-frame PNG animation, plus
// the built-in HeroAnim sequences. ~2,990 files, ~254 MB.
//
// This lives in its own package purely so the art does not reach iOS.
// SwiftPM copies a target's `resources:` into *every* product that links
// it, with no per-platform filter, so while these sat in DorisUI they were
// embedded in the iPhone app AND duplicated again inside the widget
// extension — 508 MB of macOS-only artwork in a build that never draws a
// single frame of it. The code that reads them (CharacterPack,
// AnimatedAvatarPlayer) has always been `#if os(macOS)`.
//
// DorisUI now depends on this package under `.when(platforms: [.macOS])`,
// so iOS never links it and never carries the art.
let package = Package(
    name: "DorisCharacters",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DorisCharacters", targets: ["DorisCharacters"])
    ],
    targets: [
        .target(
            name: "DorisCharacters",
            path: "Sources/DorisCharacters",
            resources: [
                .copy("HeroAnim"),
                .copy("Characters")
            ]
        )
    ]
)
