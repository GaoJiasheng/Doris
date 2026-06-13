import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Applies the selected character pack's **app icon** — the desktop / Dock /
/// home-screen icon, distinct from the in-app avatar.
///
/// The two platforms work very differently:
///
/// - **macOS** — fully runtime. We swap the running **Dock tile** via
///   `NSApp.applicationIconImage` using the pack's `icon.png`. Setting it to
///   `nil` restores the bundled icon. (The file's Finder icon is fixed at
///   build time and can't change per-user; the Dock tile is what users see
///   while the app runs.)
///
/// - **iOS** — compile-time. iOS only allows switching to **alternate icons
///   that were bundled into the asset catalog at build time** (the iOS target
///   sets `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`, and each
///   icon-bearing pack adds an "iOS App Icon" set named `AppIcon-<id>`). At
///   runtime we call `setAlternateIconName("AppIcon-<id>")` (or `nil` for the
///   primary icon). If a pack's alternate isn't bundled, the call errors and
///   we no-op — so this is safe to ship before any pack icons exist.
///   Note: iOS shows a system "You have changed the icon" alert on switch —
///   that's unavoidable OS behavior.
@MainActor
public enum AppIconManager {

    /// Apply `pack`'s app icon. Safe to call repeatedly; on iOS it no-ops
    /// when the desired icon already matches the current one.
    public static func apply(_ pack: CharacterPack) {
        #if os(macOS)
        // nil → AppKit restores the bundle icon for packs without one.
        NSApp.applicationIconImage = CharacterPackStore.shared.appIconImage(for: pack)
        #else
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let desired = pack.alternateIconName            // nil = primary icon
        guard desired != UIApplication.shared.alternateIconName else { return }
        UIApplication.shared.setAlternateIconName(desired) { error in
            if let error {
                #if DEBUG
                print("[AppIconManager] alternate icon \(desired ?? "primary") failed: \(error.localizedDescription)")
                #endif
            }
        }
        #endif
    }

    /// Re-apply the currently-selected pack's icon. Call once at launch
    /// (selection changes are handled by `CharacterPackStore`).
    public static func applyCurrent() {
        apply(CharacterPackStore.shared.selected)
    }
}
