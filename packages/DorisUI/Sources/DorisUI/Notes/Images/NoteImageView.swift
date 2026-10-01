import SwiftUI
import SwiftData
import DorisCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One body image outside the text editor — a checklist's image row, the
/// iOS reading view. Drawn at its chosen fraction of the available width;
/// tap (click) it for sizes, full size and delete, same as in the editor.
public struct NoteImageView: View {
    let ref: NoteImageRef
    /// Nil makes it read-only: tapping just shows it full size.
    var onResize: ((NoteImageSize) -> Void)?
    var onDelete: (() -> Void)?

    @Environment(\.modelContext) private var ctx
    @Environment(\.displayScale) private var scale
    @State private var image: HeroPlatformImage?
    #if os(iOS)
    @State private var viewing: ViewedImage?
    #endif

    public init(ref: NoteImageRef, onResize: ((NoteImageSize) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.ref = ref
        self.onResize = onResize
        self.onDelete = onDelete
    }

    public var body: some View {
        FractionWidthLayout(fraction: ref.size.widthFraction, aspect: NoteImageLoader.shared.aspect(ref.id, in: ctx)) {
            picture
        }
        // Its line can sync before its bytes: look again until they're here.
        .task(id: ref.id) {
            while !Task.isCancelled {
                image = NoteImageLoader.shared.image(ref.id, maxPixel: 1024 * scale, in: ctx)
                if image != nil { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $viewing) { NoteImageViewer(data: $0.data) }
        #endif
    }

    @ViewBuilder
    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: NoteImageLoader.cornerRadius, style: .continuous)
        let content = Group {
            if let image {
                #if os(macOS)
                Image(nsImage: image).resizable()
                #else
                Image(uiImage: image).resizable()
                #endif
            } else {
                shape.fill(Color.secondary.opacity(0.08))
                    .overlay(shape.stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    .overlay(Text(NoteImageLoader.syncingText).font(.caption).foregroundStyle(.secondary))
            }
        }
        .clipShape(shape)
        .contentShape(shape)

        #if os(macOS)
        content
            .onTapGesture {
                if onResize == nil { viewFull() } else { popUpMenu() }
            }
            .contextMenu { menuItems }
        #else
        if onResize == nil {
            content.onTapGesture { viewFull() }
        } else {
            Menu { menuItems } label: { content }
                .buttonStyle(.plain)
        }
        #endif
    }

    @ViewBuilder
    private var menuItems: some View {
        if let onResize {
            Picker(L("Size", "尺寸"), selection: Binding(get: { ref.size }, set: onResize)) {
                ForEach(NoteImageSize.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        }
        Button(L("View Full Size", "查看大图"), systemImage: "arrow.up.left.and.arrow.down.right") { viewFull() }
            .disabled(image == nil)
        if let onDelete {
            Button(L("Delete Image", "删除图片"), systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private func viewFull() {
        #if os(macOS)
        NoteImageActions.openFullSize(ref.id, in: ctx)
        #else
        if let data = NoteImageLoader.shared.fullData(ref.id, in: ctx) {
            viewing = ViewedImage(data: data)
        }
        #endif
    }

    #if os(macOS)
    /// A click pops the same menu the editor shows for an image.
    private func popUpMenu() {
        NoteImageActions.menu(current: ref.size, canView: image != nil,
                              onResize: { onResize?($0) },
                              onView: { viewFull() },
                              onDelete: { onDelete?() })
            .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    #endif
}

#if os(iOS)
private struct ViewedImage: Identifiable {
    let id = UUID()
    let data: Data
}
#endif

/// Takes the full proposed width and is as tall as an image `fraction` of
/// that width would be; the image sits at the leading edge.
struct FractionWidthLayout: Layout {
    var fraction: CGFloat
    var aspect: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        return CGSize(width: width, height: (width * fraction * aspect).rounded())
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = CGSize(width: (bounds.width * fraction).rounded(), height: bounds.height)
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

#if os(macOS)
/// The image menu and "view full size", shared by the body editor and the
/// checklist's image rows.
@MainActor
enum NoteImageActions {
    static func menu(current: NoteImageSize, canView: Bool,
                     onResize: @escaping (NoteImageSize) -> Void,
                     onView: @escaping () -> Void,
                     onDelete: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for size in NoteImageSize.allCases {
            let item = ClosureMenuItem(title: size.label) { onResize(size) }
            item.state = current == size ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let view = ClosureMenuItem(title: L("View Full Size", "查看大图"), action: onView)
        view.isEnabled = canView
        menu.addItem(view)
        menu.addItem(ClosureMenuItem(title: L("Delete Image", "删除图片"), action: onDelete))
        return menu
    }

    /// Opens the full-resolution image in the default viewer (Preview).
    static func openFullSize(_ id: UUID, in context: ModelContext) {
        guard let data = NoteImageLoader.shared.fullData(id, in: context) else { NSSound.beep(); return }
        let ext = NoteImageStore.attachment(id, in: context)?.mimeType == "image/png" ? "png" : "jpg"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Doris-\(id.uuidString.prefix(8)).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not coded") }

    @objc private func fire() { handler() }
}
#endif
