import SwiftUI
import SwiftData
import DorisCore

public struct NoteEditorView: View {
    @Bindable public var note: Note
    @Environment(\.modelContext) private var modelContext

    public init(note: Note) {
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $note.title)
                .font(.title2)
                .textFieldStyle(.plain)
            if note.isChecklist {
                ChecklistEditorView(note: note)
            } else {
                #if os(macOS)
                NoteBodyEditor(note: note, inset: .zero)
                #else
                TextEditor(text: $note.bodyMarkdown)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                #endif
            }
            HStack {
                Toggle(L("Checklist", "清单"), isOn: $note.isChecklist)
                    .toggleStyle(.button)
                Toggle(L("Pinned", "置顶"), isOn: $note.pinned)
                    .toggleStyle(.button)
                Spacer()
                let tags = note.tags ?? []
                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags) { tag in
                            TagChipView(name: tag.name, colorHex: tag.colorHex)
                        }
                    }
                }
            }
            .font(.caption)
        }
        .padding(16)
        .onChange(of: note.bodyMarkdown) { _, _ in note.touch() }
        .onChange(of: note.title)        { _, _ in note.touch() }
    }
}
