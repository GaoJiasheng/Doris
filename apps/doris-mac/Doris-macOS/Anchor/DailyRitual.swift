import Foundation
import DorisUI

/// Morning / evening rituals for the avatar. Fires at most once per
/// calendar day so opening Doris twice on the same morning doesn't
/// trigger a second greeting.
@MainActor
enum DailyRitual {

    private static let lastGreetKey = "doris.ritual.lastGreetDay"

    /// Fire a greeting on the first panel expand of each calendar day.
    /// Quiet mode (activityLevel == 0) suppresses the greeting.
    static func greetIfNewDay() {
        guard HeroEvents.shared.activityLevel > 0 else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let lastGreet = UserDefaults.standard.object(forKey: lastGreetKey) as? Date ?? .distantPast
        guard today > lastGreet else { return }
        UserDefaults.standard.set(today, forKey: lastGreetKey)
        // Small delay so the avatar has finished its first layout pass
        // before the greeting clip starts.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            HeroEvents.shared.greet()
        }
    }
}
