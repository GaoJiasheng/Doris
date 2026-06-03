import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Content of a desktop sticky window — an editable mini-view of one
/// note. Bound straight to the @Model `Note` from the shared container,
/// so edits here persist + sync exactly like the main editor. The
/// window chrome (drag, float, position) is handled by StickyPanel.
struct StickyNoteView: View {
    @Bindable var note: Note
    let onClose: () -> Void
    @ObservedObject private var theme = ThemeSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header — drag affordance on the left, close (unstick) on
            // the right. Whole window is movable-by-background, so the
            // grip is just a visual hint.
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.3))
                if note.isCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(CyberPalette.doneAccent)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(L("Remove from desktop", "从桌面移除"))
            }

            TextField(L("Title", "标题"), text: $note.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .strikethrough(note.isCompleted, color: CyberPalette.doneAccent.opacity(0.85))
                .onChange(of: note.title) { _, _ in note.touch() }

            Divider().overlay(Color.primary.opacity(0.08))

            ScrollView {
                if note.isChecklist {
                    ChecklistEditorView(note: note)
                } else {
                    TextEditor(text: $note.bodyMarkdown)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 12))
                        .frame(minHeight: 60)
                        .onChange(of: note.bodyMarkdown) { _, _ in note.touch() }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CyberPalette.backdrop.opacity(0.92))
                // Same pink/cyan corner glow signature as the desktop
                // panel + iOS widget, so the desktop surfaces feel like
                // one family.
                RadialGradient(colors: [CyberPalette.neonCyan.opacity(0.14), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 150)
                RadialGradient(colors: [CyberPalette.neonPink.opacity(0.10), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 130)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CyberPalette.panelStroke, lineWidth: 0.9)
        )
        .preferredColorScheme(theme.mode.colorScheme)
    }
}
