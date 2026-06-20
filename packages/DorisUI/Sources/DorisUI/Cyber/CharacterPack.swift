import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A swappable visual identity for Doris — the animated character, the
/// menu-bar portrait, an optional in-app logo, and a selection thumbnail,
/// packaged together. Users pick a pack in Settings and the whole app's
/// look changes. The built-in "小姑娘" is pack `girl`.
///
/// Adding a pack is data-only: drop a folder into
/// `DorisUI/Sources/DorisUI/Characters/<id>/` with a `pack.json` manifest
/// and assets (see `docs/character-packs.md`). `CharacterPackStore`
/// discovers it at launch — no code change.
///
/// Asset layout inside `Bundle.module`:
/// ```
/// Characters/<id>/pack.json
/// Characters/<id>/portrait.png            (menu-bar head)
/// Characters/<id>/anim/<mood>/<mood>_0001.png …   (frame sequences)
/// Characters/<id>/logo.png   (optional, in-app branding)
/// Characters/<id>/thumb.png  (optional, selector thumbnail)
/// ```

// MARK: - Manifest (pack.json)

/// Decoded `pack.json`. Only `id` + `displayName` are required.
public struct CharacterManifest: Decodable {
    public let id: String
    public let displayName: String
    public let displayNameEN: String?
    public let moods: [String]?
    public let fps: Double?
    public let loopFps: Double?
    /// Optional per-pack color theme. Any subset of colors may be set; the
    /// rest fall back to the girl defaults.
    public let theme: ThemeManifest?
    /// Internal escape hatch for the built-in `girl` pack, whose frames
    /// live in the legacy `HeroAnim/` directory rather than
    /// `Characters/girl/anim/`. New packs omit this.
    public let animDirectoryOverride: String?
}

/// The `theme` object in `pack.json`. Each color is optional and accepts
/// either a single hex string (same in both light/dark) or a
/// `{ "light": "#…", "dark": "#…" }` pair.
public struct ThemeManifest: Decodable {
    public let accentPrimary: ThemeColorSpec?     // → neonPink
    public let accentSecondary: ThemeColorSpec?   // → neonCyan
    public let done: ThemeColorSpec?              // → doneAccent
    public let backdropTop: ThemeColorSpec?
    public let backdropBottom: ThemeColorSpec?

    /// Resolve into a `CharacterTheme`, filling any missing color from girl.
    public func resolved() -> CharacterTheme {
        let g = CharacterTheme.girl
        return CharacterTheme(
            neonPink:       accentPrimary?.color(or: g.neonPink)       ?? g.neonPink,
            neonCyan:       accentSecondary?.color(or: g.neonCyan)     ?? g.neonCyan,
            doneAccent:     done?.color(or: g.doneAccent)              ?? g.doneAccent,
            backdropTop:    backdropTop?.color(or: g.backdropTop)      ?? g.backdropTop,
            backdropBottom: backdropBottom?.color(or: g.backdropBottom) ?? g.backdropBottom
        )
    }
}

/// One themed color from the manifest: `"#RRGGBB"` (optionally `#RRGGBBAA`)
/// or `{ "light": "#…", "dark": "#…" }`. Decodes from either shape.
public struct ThemeColorSpec: Decodable {
    public let light: String
    public let dark: String

    enum CodingKeys: String, CodingKey { case light, dark }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            light = single; dark = single
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let l = try c.decode(String.self, forKey: .light)
            light = l
            dark = (try c.decodeIfPresent(String.self, forKey: .dark)) ?? l
        }
    }

    /// Build the adaptive `Color`, or `fallback` if either hex is malformed.
    public func color(or fallback: Color) -> Color {
        guard let l = Color(hex: light), let d = Color(hex: dark) else { return fallback }
        return Color(light: l, dark: d)
    }
}

// MARK: - Pack

public struct CharacterPack: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let displayNameEN: String
    /// Moods this pack actually ships frames for. A requested mood not in
    /// this set falls back to `idle` (see `clip(for:)`).
    public let availableMoods: Set<String>
    /// Frame rate for one-shot moods (greeting/celebrating/…).
    public let fps: Double
    /// Frame rate for looping moods (idle/listening/…).
    public let loopFps: Double
    /// Subdirectory in `Bundle.module` holding the per-mood frame folders.
    /// Default `Characters/<id>/anim`; `girl` overrides to legacy `HeroAnim`.
    public let animDirectory: String
    /// Subdirectory in `Bundle.module` holding portrait/thumb/logo PNGs.
    public let resourceDirectory: String
    /// Whether the pack ships an `icon.png` (its app-icon source). Drives
    /// the macOS Dock-tile swap and signals that an iOS alternate icon
    /// `AppIcon-<id>` is expected in the asset catalog.
    public let hasCustomIcon: Bool
    /// The pack's color theme (the "主题" part of the set). Defaults to girl;
    /// `pack.json`'s `theme` block overrides any subset.
    public let theme: CharacterTheme

    public static func == (a: CharacterPack, b: CharacterPack) -> Bool { a.id == b.id }

    /// Resolve a requested mood-clip to one this pack can actually play,
    /// falling back to `idle` so a half-finished pack never renders blank.
    public func clip(for mood: String) -> String {
        availableMoods.contains(mood) ? mood : "idle"
    }

    /// iOS alternate-icon asset name, or nil to use the primary app icon.
    /// Convention: an "iOS App Icon" set named `AppIcon-<id>` compiled into
    /// the catalog (the iOS target sets
    /// `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`). nil for the
    /// default girl and any pack without a custom icon (→ primary icon).
    public var alternateIconName: String? {
        (hasCustomIcon && id != "girl") ? "AppIcon-\(id)" : nil
    }

    /// The always-present built-in. Used as the default selection and as a
    /// safety net if discovery finds nothing.
    public static let girl = CharacterPack(
        id: "girl",
        displayName: "小姑娘",
        displayNameEN: "Doris",
        availableMoods: ["idle", "greeting", "alerted", "listening", "celebrating", "walking", "confused"],
        fps: 16,
        loopFps: 12,
        animDirectory: "HeroAnim",
        resourceDirectory: "Characters/girl",
        hasCustomIcon: false,
        theme: .girl
    )
}

// MARK: - Store

/// Discovers the installed character packs, owns the user's selection, and
/// resolves a pack's images. Observe it (`@ObservedObject`) so the avatar +
/// portrait switch live when the selection changes.
@MainActor
public final class CharacterPackStore: ObservableObject {
    public static let shared = CharacterPackStore()

    @Published public private(set) var available: [CharacterPack]
    @Published public var selectedID: String {
        didSet {
            guard selectedID != oldValue else { return }
            UserDefaults.standard.set(selectedID, forKey: Self.key)
            // Re-skin the palette to the new pack's theme. Surfaces that
            // observe this store (or get re-rendered) pick up the colors;
            // a relaunch guarantees every surface is consistent.
            CyberPalette.activeTheme = selected.theme
            // Follow the pack with the app/Dock icon (macOS now; iOS swaps
            // the pre-bundled alternate icon if one exists for this pack).
            AppIconManager.apply(selected)
        }
    }

    private static let key = "doris.character.selectedPack"

    private init() {
        let packs = Self.discover()
        self.available = packs
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? CharacterPack.girl.id
        self.selectedID = packs.contains(where: { $0.id == saved }) ? saved : (packs.first?.id ?? CharacterPack.girl.id)
        // Apply the selected pack's theme before any surface renders.
        CyberPalette.activeTheme = (packs.first(where: { $0.id == self.selectedID }) ?? .girl).theme
    }

    /// The currently-selected pack (never nil — falls back to `girl`).
    public var selected: CharacterPack {
        available.first(where: { $0.id == selectedID })
            ?? available.first
            ?? .girl
    }

    /// Re-scan the bundle for packs (e.g. after a hot asset drop in dev).
    public func reload() { available = Self.discover() }

    // MARK: Image resolution

    public func portraitImage(for pack: CharacterPack? = nil) -> HeroPlatformImage? {
        let p = pack ?? selected
        return Self.image(named: "portrait", in: p.resourceDirectory)
            ?? Self.legacyGirlPortrait(p)
    }

    public func thumbImage(for pack: CharacterPack) -> HeroPlatformImage? {
        Self.image(named: "thumb", in: pack.resourceDirectory) ?? portraitImage(for: pack)
    }

    public func logoImage(for pack: CharacterPack? = nil) -> HeroPlatformImage? {
        Self.image(named: "logo", in: (pack ?? selected).resourceDirectory)
    }

    /// The small pixel-art mark for the menu-bar / notch (~22–26pt). When a
    /// pack ships `notch.png`, surfaces render it nearest-neighbor and
    /// square (no circle crop) so the pixels stay crisp. Returns nil when
    /// the pack has no dedicated mark — callers then fall back to the
    /// circle-cropped portrait.
    public func notchImage(for pack: CharacterPack? = nil) -> HeroPlatformImage? {
        Self.image(named: "notch", in: (pack ?? selected).resourceDirectory)
    }

    /// The pack's app-icon source (`icon.png`). Used on macOS to set the
    /// running Dock tile. nil if the pack ships no icon.
    public func appIconImage(for pack: CharacterPack? = nil) -> HeroPlatformImage? {
        Self.image(named: "icon", in: (pack ?? selected).resourceDirectory)
    }

    /// Portrait of the currently-selected pack, resolvable from any thread
    /// without main-actor isolation — it reads only `UserDefaults` + the
    /// bundle. For AppKit call sites (status-bar item, anchor view) that
    /// build an `NSImage` outside SwiftUI's observation. SwiftUI surfaces
    /// should observe the store and use the instance `portraitImage()` so
    /// they update live when the selection changes.
    public nonisolated static func currentPortraitImage() -> HeroPlatformImage? {
        let id = UserDefaults.standard.string(forKey: key) ?? CharacterPack.girl.id
        if let img = image(named: "portrait", in: "Characters/\(id)") { return img }
        #if os(macOS)
        if id == CharacterPack.girl.id {
            for sub in ["Avatar", nil] as [String?] {
                if let url = Bundle.main.url(forResource: "doris-avatar", withExtension: "png", subdirectory: sub),
                   let img = NSImage(contentsOf: url) { return img }
            }
        }
        #endif
        return nil
    }

    /// Notch/menu-bar pixel mark for the currently-selected pack, resolvable
    /// without main-actor isolation (for AppKit call sites like the status
    /// item). nil when the pack ships no `notch.png`.
    public nonisolated static func currentNotchImage() -> HeroPlatformImage? {
        let id = UserDefaults.standard.string(forKey: key) ?? CharacterPack.girl.id
        return image(named: "notch", in: "Characters/\(id)")
    }

    // MARK: Discovery

    private static func discover() -> [CharacterPack] {
        var packs: [CharacterPack] = []
        if let root = Bundle.module.resourceURL?.appendingPathComponent("Characters"),
           FileManager.default.fileExists(atPath: root.path) {
            let dirs = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for dir in dirs {
                // Skip scaffolding / hidden dirs (e.g. `_template`) so they
                // never show up as a selectable pack.
                let name = dir.lastPathComponent
                if name.hasPrefix("_") || name.hasPrefix(".") { continue }
                guard let data = try? Data(contentsOf: dir.appendingPathComponent("pack.json")),
                      let m = try? JSONDecoder().decode(CharacterManifest.self, from: data)
                else { continue }
                let resourceDir = "Characters/\(m.id)"
                let animDir = m.animDirectoryOverride ?? "\(resourceDir)/anim"
                let moods = Set(m.moods ?? detectMoods(animDir: animDir))
                let hasIcon = Bundle.module.url(
                    forResource: "icon", withExtension: "png", subdirectory: resourceDir) != nil
                packs.append(CharacterPack(
                    id: m.id,
                    displayName: m.displayName,
                    displayNameEN: m.displayNameEN ?? m.displayName,
                    availableMoods: moods.isEmpty ? ["idle"] : moods,
                    fps: m.fps ?? 16,
                    loopFps: m.loopFps ?? 12,
                    animDirectory: animDir,
                    resourceDirectory: resourceDir,
                    hasCustomIcon: hasIcon,
                    theme: m.theme?.resolved() ?? .girl
                ))
            }
        }
        if !packs.contains(where: { $0.id == CharacterPack.girl.id }) {
            packs.insert(.girl, at: 0)
        }
        // Stable order: built-in girl first, then alphabetical.
        return packs.sorted {
            ($0.id == "girl" ? "\u{0}" : $0.displayName) < ($1.id == "girl" ? "\u{0}" : $1.displayName)
        }
    }

    private static func detectMoods(animDir: String) -> [String] {
        guard let root = Bundle.module.resourceURL?.appendingPathComponent(animDir),
              FileManager.default.fileExists(atPath: root.path) else { return [] }
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return dirs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
    }

    nonisolated private static func image(named: String, in subdir: String) -> HeroPlatformImage? {
        guard let url = Bundle.module.url(forResource: named, withExtension: "png", subdirectory: subdir)
        else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url)
        #else
        return (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
        #endif
    }

    /// macOS app-bundle fallback for the original girl portrait, in case
    /// the packaged `Characters/girl/portrait.png` is ever missing.
    private static func legacyGirlPortrait(_ pack: CharacterPack) -> HeroPlatformImage? {
        guard pack.id == "girl" else { return nil }
        #if os(macOS)
        for sub in ["Avatar", nil] as [String?] {
            if let url = Bundle.main.url(forResource: "doris-avatar", withExtension: "png", subdirectory: sub),
               let img = NSImage(contentsOf: url) { return img }
        }
        #endif
        return nil
    }
}
