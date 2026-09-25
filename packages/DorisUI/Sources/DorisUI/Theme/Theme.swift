import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum DorisColors {
    public static let accent = Color.accentColor
    public static let pinned = Color.orange
    public static let bannerBackground = Color(white: 0.12)
    public static let cardBackground = Color.secondary.opacity(0.06)
}

/// Shared neon palette used across every surface (panel, weather bubble,
/// voice floater, iOS hero, main window). Backdrop colors flip between dark
/// and light variants automatically when the user toggles `ThemeSettings`,
/// because we apply `.preferredColorScheme(...)` at the scene root and these
/// colors are built from `Color(light:dark:)`.
///
/// The neon accents (pink/cyan) stay the same in both modes — they're brand
/// — but get slightly muted overlay alpha-values when used on light
/// backgrounds so they don't burn the eyes.
/// The themeable colors of a character pack — the "主题" half of a pack
/// (the rest is logo / character / portrait / icon assets). Every field has
/// a sensible girl default, so a pack's `pack.json` may override any subset
/// (or none). `CyberPalette` reads the *active* theme, so changing the
/// selected pack re-skins every surface that uses the palette.
public struct CharacterTheme: Equatable {
    /// Primary brand accent (maps to `CyberPalette.neonPink`).
    public let neonPink: Color
    /// Secondary brand accent (maps to `CyberPalette.neonCyan`).
    public let neonCyan: Color
    /// "Completed / done" accent.
    public let doneAccent: Color
    /// Top + bottom of the adaptive page backdrop gradient.
    public let backdropTop: Color
    public let backdropBottom: Color

    public init(neonPink: Color, neonCyan: Color, doneAccent: Color,
                backdropTop: Color, backdropBottom: Color) {
        self.neonPink = neonPink
        self.neonCyan = neonCyan
        self.doneAccent = doneAccent
        self.backdropTop = backdropTop
        self.backdropBottom = backdropBottom
    }

    /// The built-in cyber-girl palette — also the fallback for any color a
    /// pack doesn't override. These are the exact values the app shipped
    /// before theming existed, so the girl pack looks identical.
    public static let girl = CharacterTheme(
        neonPink: Color(
            light: Color(red: 0.80, green: 0.10, blue: 0.55),
            dark:  Color(red: 1.0,  green: 0.30, blue: 0.75)
        ),
        neonCyan: Color(
            light: Color(red: 0.00, green: 0.55, blue: 0.75),
            dark:  Color(red: 0.0,  green: 0.85, blue: 1.0)
        ),
        doneAccent: Color(
            light: Color(red: 0.42, green: 0.46, blue: 0.52),
            dark:  Color(red: 0.62, green: 0.66, blue: 0.72)
        ),
        backdropTop: Color(
            light: Color(red: 0.94, green: 0.93, blue: 0.98),
            dark:  Color(red: 0.10, green: 0.06, blue: 0.18)
        ),
        backdropBottom: Color(
            light: Color(red: 0.99, green: 0.97, blue: 1.00),
            dark:  Color(red: 0.02, green: 0.02, blue: 0.05)
        )
    )
}

extension CharacterTheme {
    /// The default pack's (cat) theme, compiled in — the exact `theme`
    /// object from `Characters/cat/pack.json`.
    ///
    /// `pack.json` is the source of truth, but it now ships only inside the
    /// macOS-only character-art bundle. iOS and the app extensions have no
    /// packs to choose between and no manifest to read, and without this
    /// they fell back to `.girl` — the pre-theming pink/cyan — so from 1.8.1
    /// the iPhone stopped looking like the Mac. `DefaultPackThemeTests`
    /// fails if this drifts from the manifest.
    static let defaultPackThemeJSON = """
    {
      "accentPrimary":   { "light": "#1F6FD1", "dark": "#5CC8FF" },
      "accentSecondary": { "light": "#0A7F9E", "dark": "#74E4FF" },
      "done":            "#9AA0A6",
      "backdropTop":     { "light": "#EEF2F6", "dark": "#0E1925" },
      "backdropBottom":  { "light": "#F8FAFC", "dark": "#05080F" }
    }
    """

    public static let defaultPack: CharacterTheme = {
        let manifest = try? JSONDecoder().decode(ThemeManifest.self,
                                                 from: Data(defaultPackThemeJSON.utf8))
        return manifest?.resolved() ?? .girl
    }()
}

public enum CyberPalette {
    // MARK: Active theme (set by CharacterPackStore on launch + pack switch)

    /// The selected pack's theme. Starts as the default pack's, which is
    /// also what any process that never loads the pack store keeps — the
    /// iOS widget and the share extensions. Mutated on the main actor (UI)
    /// only.
    public static var activeTheme: CharacterTheme = .defaultPack

    // MARK: Brand accents (now resolved from the active pack's theme)

    /// Neon pink — vivid in dark mode, deepened in light for legibility.
    public static var neonPink: Color { activeTheme.neonPink }
    /// Neon cyan — vivid in dark mode, ocean-teal in light for legibility.
    public static var neonCyan: Color { activeTheme.neonCyan }
    /// Accent used for "completed / done" UI — strikethrough color, DONE
    /// pill, completed-card border, seal icon.
    public static var doneAccent: Color { activeTheme.doneAccent }

    /// Success green — the focus ring's "session complete" checkmark. Not
    /// themeable: "finished" should read the same in every character pack
    /// (and `doneAccent` is a muted grey, not a completion signal).
    public static let neonGreen = Color(
        light: Color(red: 0.05, green: 0.55, blue: 0.30),
        dark:  Color(red: 0.20, green: 0.95, blue: 0.55)
    )

    /// "Due today" on date chips. Was plain `.yellow`, which is 1.5:1 on a
    /// white card — the label all but vanished in light mode. Deep amber in
    /// light (5.2:1); dark keeps the system yellow it always had.
    public static let todayAccent = Color(
        light: Color(red: 0.63, green: 0.36, blue: 0.00),
        dark:  .yellow
    )

    /// Critical events — the notch card's wash and edge, the events list's
    /// stripe and badge. Fixed, not themed: critical was drawn in
    /// `neonPink` back when that was always pink, and once packs recolored
    /// `neonPink` it became cat's blue (the same as info) and clip's gold
    /// (the same as a reminder's orange). These are the original pinks.
    public static let alert = Color(
        light: Color(red: 0.80, green: 0.10, blue: 0.55),
        dark:  Color(red: 1.0,  green: 0.30, blue: 0.75)
    )

    /// "Overdue" on date chips. System red is 3.5:1 on white — deepened in
    /// light (5.3:1); dark unchanged.
    public static let overdueAccent = Color(
        light: Color(red: 0.80, green: 0.18, blue: 0.15),
        dark:  .red
    )

    // MARK: Adaptive backdrop (themeable)

    public static var backdropTop: Color { activeTheme.backdropTop }
    public static var backdropBottom: Color { activeTheme.backdropBottom }

    /// Surface used for cards / list rows. Glass-fill in dark, near-solid
    /// white in light. The light values used to be 0.85 → 0.65, which let
    /// the tinted backdrop straight through: cards read as the page itself.
    public static let surfaceTop = Color(
        light: Color.white.opacity(0.96),
        dark:  Color.black.opacity(0.55)
    )

    public static let surfaceBottom = Color(
        light: Color.white.opacity(0.92),
        dark:  Color.black.opacity(0.30)
    )

    /// Row fill for grouped lists (Settings). Dark keeps the faint 5% lift
    /// it always had; light gets white rows, the same as the light cards —
    /// `primary.opacity(0.05)` there is a grey row on a grey page.
    public static let listRowFill = Color(
        light: Color.white,
        dark:  Color.white.opacity(0.05)
    )

    // MARK: Composed gradients

    public static var backdrop: LinearGradient {
        LinearGradient(
            colors: [backdropTop, backdropBottom],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Full-brightness gradient stroke — use for the active banner and
    /// pinned-first card only. Keeps the "glowing" effect rare so it
    /// reads as meaningful rather than decorative noise.
    public static var panelStroke: LinearGradient {
        LinearGradient(
            colors: [neonPink.opacity(0.45), neonCyan.opacity(0.55)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Muted stroke for secondary cards and panels — same gradient but
    /// at ~30% opacity so the eye can still see the cyber aesthetic
    /// without every surface competing for attention.
    public static var dimPanelStroke: LinearGradient {
        LinearGradient(
            colors: [neonPink.opacity(0.14), neonCyan.opacity(0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public static var surfaceFill: LinearGradient {
        LinearGradient(
            colors: [surfaceTop, surfaceBottom],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Color(light:dark:) helper

public extension Color {
    /// Build a color that switches based on the active `colorScheme`. Use this
    /// for any surface that should flip between the dark and light cyber
    /// modes; brand accents (pink/cyan) typically don't need it.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self = Color(NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return NSColor(dark)
            default:        return NSColor(light)
            }
        })
        #else
        self = Color(UIColor { trait in
            switch trait.userInterfaceStyle {
            case .dark: return UIColor(dark)
            default:    return UIColor(light)
            }
        })
        #endif
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        var rgba: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgba) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((rgba & 0xFF0000) >> 16) / 255
            g = Double((rgba & 0x00FF00) >> 8) / 255
            b = Double(rgba & 0x0000FF) / 255
            a = 1
        } else {
            r = Double((rgba & 0xFF000000) >> 24) / 255
            g = Double((rgba & 0x00FF0000) >> 16) / 255
            b = Double((rgba & 0x0000FF00) >> 8) / 255
            a = Double(rgba & 0x000000FF) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
