import Foundation
import SwiftData
import DorisCore

/// Adds images from a toolbar button (photo picker, open panel) to a note.
///
/// A text note's open editor takes them at its cursor; it answers the
/// request synchronously by marking it handled. Otherwise — a checklist,
/// whose rows have no cursor once the picker has taken focus, or no
/// editor on screen any more — they go at the end of the body.
@MainActor
public enum NoteImageInsertion {
    public final class Request {
        public let noteID: UUID
        public let datas: [Data]
        public var handled = false

        init(noteID: UUID, datas: [Data]) {
            self.noteID = noteID
            self.datas = datas
        }
    }

    public static func insert(_ datas: [Data], into note: Note, context: ModelContext) {
        guard !datas.isEmpty else { return }
        if !note.isChecklist {
            let request = Request(noteID: note.id, datas: datas)
            NotificationCenter.default.post(name: .dorisInsertNoteImages, object: request)
            if request.handled { return }
        }
        let refs = datas.compactMap { NoteImageStore.add(imageData: $0, to: note, in: context) }
        guard !refs.isEmpty else { return }
        note.bodyMarkdown = appending(refs, to: note.bodyMarkdown, checklist: note.isChecklist)
        note.touch()
    }

    /// The body with image lines added at the end — in a checklist, above
    /// a trailing empty item so the blank row to type in stays last.
    static func appending(_ refs: [NoteImageRef], to body: String, checklist: Bool) -> String {
        let images = refs.map(NoteImageMarkup.line)
        guard !body.isEmpty else { return images.joined(separator: "\n") }
        var lines = body.components(separatedBy: "\n")
        let blankItem = { (line: String) in
            line.trimmingCharacters(in: .whitespaces).isEmpty || line == "- [ ] " || line == "- [ ]"
        }
        if checklist, let last = lines.last, blankItem(last) {
            lines.insert(contentsOf: images, at: lines.count - 1)
        } else {
            if lines.last == "" { lines.removeLast() }
            lines.append(contentsOf: images)
        }
        return lines.joined(separator: "\n")
    }
}

/// Whether pasteboard text alongside image data is something the user
/// meant to paste. A copied image's link is one unbroken token; prose has
/// spaces or line breaks.
enum NoteImagePasteRule {
    static func isProse(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).contains { $0.isWhitespace }
    }
}

extension Notification.Name {
    /// `object` is a `NoteImageInsertion.Request`. Observed synchronously
    /// (queue nil) by the body editors.
    public static let dorisInsertNoteImages = Notification.Name("dorisInsertNoteImages")
}
