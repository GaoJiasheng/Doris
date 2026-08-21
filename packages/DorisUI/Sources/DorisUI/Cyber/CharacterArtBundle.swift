import Foundation
#if os(macOS)
import DorisCharacters
#endif

/// Where the character artwork lives, or `nil` on platforms that don't ship it.
///
/// The art (~254 MB of frame-by-frame PNG) is a macOS-only package, because
/// SwiftPM copies a target's resources into *every* product that links it —
/// while it belonged to DorisUI it rode along into the iPhone app and was
/// duplicated again inside the widget extension, half a gigabyte that iOS
/// never draws.
///
/// The character *code* still compiles on iOS: `CharacterPack` and
/// `AnimatedAvatarPlayer` are shared source, and only their AppKit/UIKit
/// shims are `#if`'d. Nothing on iOS ever presents them — there is no
/// menu bar, notch, or desktop pet — so returning `nil` here simply makes
/// every lookup miss, which those call sites already handle as "no art".
enum CharacterArtBundle {
    static var bundle: Bundle? {
        #if os(macOS)
        DorisCharacters.bundle
        #else
        nil
        #endif
    }
}
