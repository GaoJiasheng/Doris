import Foundation
import SwiftUI
import Combine
import DorisUI

/// How often the avatar reacts to task events and notifications.
public enum AvatarActivityLevel: String, CaseIterable {
    case quiet    = "quiet"    // one-shots only on direct user interaction
    case standard = "standard" // reactions on task completion + agent banners (default)
    case lively   = "lively"   // reactions on every event
}

/// Whether the cyber-girl avatar ("小姑娘") pane is shown in the main
/// window sidebar + the menu-bar dropdown. Persisted in `UserDefaults`
/// so a collapse sticks across launches — this single value doubles as
/// both the live state (toggled from either surface) and the remembered
/// default the Settings toggle exposes.
@MainActor
final class AvatarSettings: ObservableObject {
    static let shared = AvatarSettings()

    @Published var avatarVisible: Bool {
        didSet { UserDefaults.standard.set(avatarVisible, forKey: Self.visibleKey) }
    }

    @Published var activityLevel: AvatarActivityLevel {
        didSet { UserDefaults.standard.set(activityLevel.rawValue, forKey: Self.activityKey) }
    }

    private static let visibleKey  = "doris.avatar.visible"
    private static let activityKey = "doris.avatar.activityLevel"

    private init() {
        if let raw = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool {
            self.avatarVisible = raw
        } else {
            self.avatarVisible = true
        }
        if let raw = UserDefaults.standard.string(forKey: Self.activityKey),
           let level = AvatarActivityLevel(rawValue: raw) {
            self.activityLevel = level
        } else {
            self.activityLevel = .standard
        }
    }

    /// Fire a task-completion celebration, respecting the activity level.
    /// Quiet mode never auto-celebrates; standard/lively always do.
    func celebrateTaskDone() {
        guard activityLevel != .quiet else { return }
        HeroEvents.shared.celebrate()
    }

    /// Fire an alert reaction (agent notification arrived). Suppressed in quiet mode.
    func alertIfAllowed() {
        guard activityLevel != .quiet else { return }
        HeroEvents.shared.alert()
    }
}
