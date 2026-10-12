import SwiftUI
import SwiftData
import UIKit
import DorisCore
import DorisUI

/// What the large Tasks widget's buttons open: `doris://quick/add`,
/// `doris://quick/focus`, `doris://quick/photo`.
enum QuickAction: String, Identifiable {
    case add, focus, photo

    var id: String { rawValue }

    init?(url: URL) {
        guard url.scheme == "doris", url.host == "quick" else { return nil }
        self.init(rawValue: url.lastPathComponent)
    }
}

// MARK: - Add a task

/// A task in one line: title, a due day (today by default — the widget
/// it came from is about today), done. From the camera it also carries
/// the photo, which goes into the task's body.
struct QuickAddSheet: View {
    var photo: Data?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var title = ""
    @State private var due: Due = .today
    @FocusState private var titleFocused: Bool

    enum Due: CaseIterable, Hashable {
        case today, tomorrow, none

        @MainActor var label: String {
            switch self {
            case .today: return L("Today", "今天")
            case .tomorrow: return L("Tomorrow", "明天")
            case .none: return L("No date", "不设日期")
            }
        }

        var date: Date? {
            let today = Calendar.current.startOfDay(for: Date())
            switch self {
            case .today: return today
            case .tomorrow: return Calendar.current.date(byAdding: .day, value: 1, to: today)
            case .none: return nil
            }
        }
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty || photo != nil }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                TextField(photo == nil ? L("What needs doing?", "要做什么?")
                                       : L("A title for this photo (optional)", "给这张照片起个标题(可不填)"),
                          text: $title)
                    .font(.title3.weight(.semibold))
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                Picker(L("Due", "日期"), selection: $due) {
                    ForEach(Due.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(photo == nil ? L("Add Task", "添加任务") : L("Photo Task", "拍照记一条"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Add", "添加"), action: save).disabled(!canSave)
                }
            }
            .onAppear {
                // A beat after the sheet lands, or the keyboard can lose
                // the race with the presentation.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { titleFocused = true }
            }
        }
        .presentationDetents(photo == nil ? [.medium, .large] : [.large])
    }

    private func save() {
        guard canSave else { return }
        let note = Note(title: trimmed.isEmpty ? Self.photoTitle() : trimmed, dueDate: due.date)
        ctx.insert(note)
        if let photo, let ref = NoteImageStore.add(imageData: photo, to: note, in: ctx) {
            note.bodyMarkdown = NoteImageMarkup.line(ref)
        }
        try? ctx.save()
        if let date = note.dueDate {
            DueDateNotifier.schedule(noteID: note.id, title: note.title, dueDate: date, done: false)
        }
        _ = WidgetReloadCoordinator.reloadIfChanged(container: ctx.container)
        dismiss()
    }

    /// "照片 10月12日 15:30" — for a photo saved without a title.
    private static func photoTitle() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L("en_US", "zh_CN"))
        f.dateFormat = L("'Photo' MMM d, HH:mm", "'照片' M月d日 HH:mm")
        return f.string(from: Date())
    }
}

// MARK: - Camera

/// The system camera; the photo library on a device without one (the
/// simulator). Hands back JPEG data, or nil when cancelled.
struct CameraPicker: UIViewControllerRepresentable {
    var onDone: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (Data?) -> Void
        init(onDone: @escaping (Data?) -> Void) { self.onDone = onDone }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onDone(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDone(nil)
        }
    }
}

// MARK: - Pick a focus

/// Which task to focus on, and for how long. Today's tasks first (what the
/// widget showed), then the rest, then a focus on nothing in particular.
struct FocusPickerSheet: View {
    var onPick: (_ noteID: UUID?, _ title: String, _ minutes: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var minutes = 25

    @Query(filter: #Predicate<Note> { !$0.archived && !$0.deleted && !$0.done },
           sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var open: [Note]

    private var today: [Note] {
        open.filter { $0.isOverdue() || $0.isDueToday() || ($0.pinned && !$0.longTerm) }
            .sorted { rank($0) < rank($1) }
    }

    private var others: [Note] {
        let ids = Set(today.map(\.id))
        return Array(open.filter { !ids.contains($0.id) }.prefix(15))
    }

    /// Overdue, then due today, then pinned.
    private func rank(_ n: Note) -> Int {
        if n.isOverdue() { return 0 }
        if n.isDueToday() { return 1 }
        return 2
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L("Length", "时长"), selection: $minutes) {
                        ForEach([15, 25, 45], id: \.self) { Text(L("\($0) min", "\($0) 分钟")).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                if !today.isEmpty {
                    Section(L("Today", "今日")) { ForEach(today) { row($0) } }
                }
                if !others.isEmpty {
                    Section(L("Other tasks", "其他任务")) { ForEach(others) { row($0) } }
                }
                Section {
                    Button {
                        onPick(nil, L("Focus", "专注"), minutes)
                    } label: {
                        Label(L("Just focus — no task", "自由专注(不绑定任务)"), systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle(L("Start a Focus", "开始专注"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "取消")) { dismiss() }
                }
            }
        }
    }

    private func row(_ note: Note) -> some View {
        Button {
            onPick(note.id, note.title, minutes)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "timer").foregroundStyle(CyberPalette.neonPink)
                Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if let p = note.checklistProgress {
                    Text("\(p.done)/\(p.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        // Plain, so titles read as text rather than blue links.
        .buttonStyle(.plain)
    }
}
