#if os(iOS)
import Foundation
import UserNotifications

/// Local notification for "focus session finished" on iOS.
///
/// The countdown itself is a 1 Hz in-process `Timer`, which stops firing as
/// soon as iOS suspends the app — so `FocusTimer.notify` alone would never
/// reach a user who locked their phone to actually focus. We therefore
/// schedule a real `UNNotificationRequest` up front (at the session's end
/// time) and cancel/reschedule it whenever the clock is stopped or held.
///
/// Authorization is already requested at launch by `DueDateNotifier`.
enum FocusNotifier {
    private static let identifier = "doris.focus.finished"

    /// (Re)arm the end-of-session alert `seconds` from now.
    static func arm(after seconds: Int, title: String, isRest: Bool) {
        cancel()
        guard seconds > 0 else { return }
        let isZh = Locale.current.language.languageCode?.identifier == "zh"
        let content = UNMutableNotificationContent()
        content.title = isRest
            ? (isZh ? "休息结束" : "Break over")
            : (isZh ? "专注结束" : "Focus done")
        content.body = title
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(seconds), repeats: false
        )
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        ) { _ in }
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
#endif
