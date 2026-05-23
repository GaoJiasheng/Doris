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
public enum CyberPalette {
    // MARK: Brand accents (constant across themes)

    public static let neonPink = Color(red: 1.0, green: 0.30, blue: 0.75)
    public static let neonCyan = Color(red: 0.0, green: 0.85, blue: 1.0)
    /// Accent used for "completed / done" UI — strikethrough color, DONE
    /// pill, completed-card border, seal icon. Earlier iterations used a
    /// vivid neon green which read as "alert" and visually fought with
    /// neonCyan; a cool mid-grey reads as "settled / archived-but-here"
    /// without competing with the brand accents. Auto-adapts so it's
    /// readable on both themes.
    public static let doneAccent = Color(
        light: Color(red: 0.42, green: 0.46, blue: 0.52),
        dark:  Color(red: 0.62, green: 0.66, blue: 0.72)
    )

    // MARK: Adaptive backdrop

    public static let backdropTop = Color(
        light: Color(red: 0.94, green: 0.93, blue: 0.98),
        dark:  Color(red: 0.10, green: 0.06, blue: 0.18)
    )

    public static let backdropBottom = Color(
        light: Color(red: 0.99, green: 0.97, blue: 1.00),
        dark:  Color(red: 0.02, green: 0.02, blue: 0.05)
    )

    /// Surface used for cards / list rows. Glass-fill in dark, soft white in
    /// light. Defined as a primary fill — the neon stroke goes on top.
    public static let surfaceTop = Color(
        light: Color.white.opacity(0.85),
        dark:  Color.black.opacity(0.55)
    )

    public static let surfaceBottom = Color(
        light: Color.white.opacity(0.65),
        dark:  Color.black.opacity(0.30)
    )

    // MARK: Composed gradients

    public static var backdrop: LinearGradient {
        LinearGradient(
            colors: [backdropTop, backdropBottom],
            startPoint: .top, endPoint: .bottom
        )
    }

    public static var panelStroke: LinearGradient {
        LinearGradient(
            colors: [neonPink.opacity(0.45), neonCyan.opacity(0.55)],
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
