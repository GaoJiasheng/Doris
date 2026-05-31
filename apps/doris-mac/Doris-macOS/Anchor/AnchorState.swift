import Foundation
import DorisIPC

enum AnchorState: Equatable {
    case idle
    case banner(message: AnchorMessage)
    case fix(message: AnchorMessage)
    case expanded
}

struct AnchorMessage: Equatable {
    let id: UUID
    let title: String
    let body: String?
    let iconName: String?
    /// Originating source. Drives the banner's leading glyph: known
    /// brands (Claude Code, Codex) render their real logo asset
    /// instead of the generic Doris avatar, so a glance tells you
    /// which agent just finished.
    let source: SourceKind?
    let level: EventLevel
    let displayMode: DisplayMode
    let receivedAt: Date
    /// What happens when the user clicks the banner card itself.
    /// `nil` → fall back to "dismiss banner + expand Doris dropdown"
    /// (the historical default for events that have no specific
    /// landing place).
    /// `.openURL(claude://)` etc. → open the originating app via
    /// LaunchServices, without expanding Doris. This is what
    /// Claude/Codex/ChatGPT integrations send so the user lands
    /// straight in the source app on click.
    let clickAction: ClickAction?
}

extension SourceKind {
    /// Asset-catalog name of this source's real brand logo, or `nil`
    /// for sources that have no dedicated logo (fall back to the Doris
    /// avatar / SF Symbol). Logos are the actual app icons extracted
    /// from the installed Claude.app / Codex.app, so they match what
    /// the user sees in their Dock.
    var brandLogoAssetName: String? {
        switch self {
        case .claudeCode: return "SourceLogoClaude"
        case .codex:      return "SourceLogoCodex"
        default:          return nil
        }
    }
}

extension EventLevel {
    /// How long an auto-dismiss banner of this level stays on screen.
    /// `critical` is sticky and never returns a finite duration; the
    /// caller routes critical through the `fix` path instead.
    var bannerDuration: TimeInterval {
        switch self {
        case .info:     return 1.5
        case .reminder: return 4.0
        case .critical: return .infinity
        }
    }
}
