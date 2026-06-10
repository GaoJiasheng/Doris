import Foundation
import Combine
import SwiftUI

/// Global event bus the avatar listens to. Lets any code path fire a mood
/// reaction without having to plumb a binding all the way down. The events
/// are timestamps so a hero can re-fire the same reaction (`celebrate()`
/// twice in a row both run).
///
/// Usage:
///   - `HeroEvents.shared.celebrate()` — when a task is done, sync finishes, etc.
///   - `HeroEvents.shared.greet()` — when the dropdown panel opens.
///   - `HeroEvents.shared.alert()` — when a notification arrives.
///   - `HeroEvents.shared.isListening = true/false` — voice capture lifecycle.
///
/// Activity level: the macOS app sets `activityLevel` at launch from the
/// user's preference. 0 = quiet (no auto-reactions), 1 = standard (default),
/// 2 = lively. Callers can pass a `minActivity` to respect this gate.
@MainActor
public final class HeroEvents: ObservableObject {
    public static let shared = HeroEvents()

    @Published public var lastCelebration: Date = .distantPast
    @Published public var lastGreeting: Date = .distantPast
    @Published public var lastAlert: Date = .distantPast
    @Published public var isListening: Bool = false

    /// 0 = quiet, 1 = standard (default), 2 = lively.
    /// Set by the macOS app from the user's preference in AvatarSettings.
    public var activityLevel: Int = 1

    private init() {}

    /// Fire a celebration reaction. Pass `minActivity: 0` for user-initiated
    /// events that should fire even in quiet mode; default `1` respects
    /// the "standard or above" gate.
    public func celebrate(minActivity: Int = 1) {
        guard activityLevel >= minActivity else { return }
        lastCelebration = Date()
    }

    /// Fire a greeting reaction. Always fires (user opened the panel).
    public func greet() { lastGreeting = Date() }

    /// Fire an alert reaction. Respects `minActivity: 1` by default.
    public func alert(minActivity: Int = 1) {
        guard activityLevel >= minActivity else { return }
        lastAlert = Date()
    }
}
