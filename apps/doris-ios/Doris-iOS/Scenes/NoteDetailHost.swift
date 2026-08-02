import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Resolves a note id to the note, once, and hands it to `NoteDetailScreen`.
///
/// Exists to decouple the open editor from the notes list's `@Query`. That
/// query is sorted by `updatedAt`, so typing in a note re-emits it — and when
/// the navigation destination read the note straight out of that array, every
/// re-emission re-evaluated the destination and rebuilt the editor's text
/// fields. Rebuilding a field while an input method has marked text force-
/// commits the composition, which is why Pinyin typing kept dropping raw
/// letters into the title as though Return had been pressed.
///
/// Resolving into `@State` here means the list can churn as much as it likes;
/// the editor above it keeps its identity and its first responder.
struct NoteDetailHost: View {
    let id: UUID
    var onDelete: () -> Void

    @Environment(\.modelContext) private var ctx
    @State private var note: Note?
    @State private var resolved = false

    var body: some View {
        Group {
            if let note {
                NoteDetailScreen(note: note, onDelete: onDelete)
            } else if resolved {
                // Fetched and genuinely absent (deleted on another device).
                Text(L("Note not found", "笔记不存在"))
                    .foregroundStyle(.secondary)
            } else {
                // First render; the fetch below runs immediately after.
                Color.clear
            }
        }
        .task {
            guard !resolved else { return }
            var fd = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
            fd.fetchLimit = 1
            note = try? ctx.fetch(fd).first
            resolved = true
        }
    }
}
