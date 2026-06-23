import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Manages the app's **launcher icon** (Dock / home-screen), distinct from
/// the in-app avatar.
///
/// The icon is intentionally FIXED to the bundled build-time icon — the
/// default Cyber Cat on a white background — for every character pack.
/// Switching a character changes the avatar, notch mark, and color theme,
/// but the launcher icon stays the cat. So `apply()` just restores the
/// build-time icon (macOS: `applicationIconImage = nil`; iOS: primary icon)
/// regardless of which pack is passed.
@MainActor
public enum AppIconManager {

    /// The app icon is FIXED to the bundled build-time icon (the default
    /// Cyber Cat, white background) for every pack — picking a character
    /// re-skins the avatar / notch / theme but NOT the Dock / home-screen
    /// icon. `pack` is ignored; we always restore the build-time icon.
    /// Safe to call repeatedly.
    public static func apply(_ pack: CharacterPack) {
        #if os(macOS)
        // nil → AppKit shows the bundled (build-time) icon, i.e. the cat.
        NSApp.applicationIconImage = nil
        #else
        // Always the primary (build-time) icon; only reset if an alternate
        // was somehow set, to avoid a needless system "icon changed" alert.
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != nil else { return }
        UIApplication.shared.setAlternateIconName(nil)
        #endif
    }

    /// Re-apply the currently-selected pack's icon. Call once at launch
    /// (selection changes are handled by `CharacterPackStore`).
    public static func applyCurrent() {
        apply(CharacterPackStore.shared.selected)
    }
}
