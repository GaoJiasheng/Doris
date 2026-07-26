import Foundation
import SwiftData
import DorisCore

/// Applies the focus dial's "完成" to the store: marks the focused note done,
/// or — for a sub-task focus — ticks the matching checklist line.
///
/// Shared by both platforms (wired into `FocusTimer.completeHandler`) so the
/// checklist markdown format is understood in exactly one place.
@MainActor
public enum FocusTaskCompleter {

    public static func complete(_ session: FocusTimer.Session) {
        guard let noteID = session.noteID else { return }
        // Its own context (fresh fetch by id) so this is safe off the main UI
        // graph; the surfaces' @Query pick the change up.
        let ctx = ModelContext(DorisRuntime.shared.container)
        var fd = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })
        fd.fetchLimit = 1
        guard let note = try? ctx.fetch(fd).first else { return }

        if let sub = session.subtaskText, !sub.isEmpty {
            note.bodyMarkdown = tickChecklistLine(note.bodyMarkdown, matching: sub)
        } else {
            note.done = true
            note.completedAt = Date()
        }
        note.updatedAt = Date()
        try? ctx.save()
    }

    /// Flip the FIRST unchecked `- [ ] <text>` line matching `text` to `- [x]`.
    static func tickChecklistLine(_ body: String, matching text: String) -> String {
        var lines = body.components(separatedBy: "\n")
        for i in lines.indices where lines[i].hasPrefix("- [ ] ") {
            if String(lines[i].dropFirst(6)) == text {
                lines[i] = "- [x] " + text
                break
            }
        }
        return lines.joined(separator: "\n")
    }
}
