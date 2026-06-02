import Foundation
import SwiftUI
import Combine

/// Whether the cyber-girl avatar ("小姑娘") pane is shown in the main
/// window sidebar + the menu-bar dropdown. Persisted in `UserDefaults`
/// so a collapse sticks across launches — this single value doubles as
/// both the live state (toggled from either surface) and the remembered
/// default the Settings toggle exposes.
@MainActor
final class AvatarSettings: ObservableObject {
    static let shared = AvatarSettings()

    @Published var avatarVisible: Bool {
        didSet {
            UserDefaults.standard.set(avatarVisible, forKey: Self.key)
        }
    }

    private static let key = "doris.avatar.visible"

    private init() {
        if let raw = UserDefaults.standard.object(forKey: Self.key) as? Bool {
            self.avatarVisible = raw
        } else {
            self.avatarVisible = true   // shown by default
        }
    }
}
