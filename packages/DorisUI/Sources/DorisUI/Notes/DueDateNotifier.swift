import Foundation
import UserNotifications

/// Schedules and cancels local `UNUserNotification` reminders for notes
/// that have a due date. One notification per note, identified by the
/// note's UUID string so it's trivially replaceable when the date changes.
///
/// Fires at 09:00 on the due day (so the user sees "due today" in the
/// morning rather than at midnight). If the due date is in the past or
/// within the next hour, fires in 5 minutes instead so setting a "due
/// today" date on an already-started day still gives feedback.
///
/// Authorization is requested lazily on the first schedule call.
/// Silently no-ops if the user denies permission — the UI already shows
/// the due date chip visually.
public enum DueDateNotifier {

    // MARK: - Public API

    /// Request authorization (provisional on iOS so it shows without asking).
    /// Safe to call multiple times — UNUserNotificationCenter dedupes.
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    /// Schedule (or replace) a reminder for `note`. No-op if note.done
    /// or note has no dueDate.
    public static func schedule(noteID: UUID, title: String, dueDate: Date, done: Bool) {
        guard !done, dueDate > Date() else {
            cancel(noteID: noteID)
            return
        }
        let identifier = "doris.due.\(noteID.uuidString)"
        let content = UNMutableNotificationContent()
        let isZh = Locale.current.language.languageCode?.identifier == "zh"
        content.title = isZh ? "今天到期" : "Due today"
        content.body  = title.isEmpty ? (isZh ? "有任务到期了" : "A task is due") : title
        content.sound = .default

        // Fire at 09:00 on the due day, or in 5 min if that's already past.
        var fireDate = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: dueDate
        ) ?? dueDate
        if fireDate < Date() { fireDate = Date().addingTimeInterval(300) }

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// Cancel any pending reminder for this note.
    public static func cancel(noteID: UUID) {
        let identifier = "doris.due.\(noteID.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
    }
}
