//  ReorderableNoteGrid.swift — DorisUI
//
//  Drag-reorder grid for Note cards, shared by every Today surface
//  (iOS + macOS). The interaction the user actually wants: as you drag a
//  card across its neighbours, each neighbour **slides out of the way live**
//  (reorder fires on HOVER, animated with a spring) and the dragged card
//  leaves a clear gap; the card snapshot follows the cursor; on release the
//  new order is persisted via `commit`.
//
//  Mechanism: the SYSTEM drag (`.onDrag` + `.dropDestination`) — the same
//  proven path the original grid used — but we reorder on the drop target's
//  `isTargeted` hover (wrapped in `withAnimation`) instead of waiting for the
//  drop. The custom-DragGesture approach was abandoned: on macOS it sat on a
//  Button and its frame-crossing reorder never animated in a LazyVGrid.
//
//  iOS 18 / macOS 14.

import SwiftUI
import DorisCore

public struct ReorderableNoteGrid<Card: View>: View {

    private let source: [Note]
    private let columns: [GridItem]
    private let spacing: CGFloat
    /// Accent for the dragged card's gap outline (cyan normally, doneAccent
    /// when completed). Site can override; the default does the right thing.
    private let accent: (Note) -> Color
    /// Builds the card; the site keeps its own tap target + context menu.
    private let card: (Note) -> Card
    /// Persist the reordered array. `moved` is the dragged note so the site
    /// can `moved.touch()` to preserve its updatedAt provenance.
    private let commit: (_ ordered: [Note], _ moved: Note) -> Void

    public init(
        _ source: [Note],
        columns: [GridItem],
        spacing: CGFloat,
        accent: @escaping (Note) -> Color = { $0.isCompleted ? CyberPalette.doneAccent : CyberPalette.neonCyan },
        @ViewBuilder card: @escaping (Note) -> Card,
        commit: @escaping (_ ordered: [Note], _ moved: Note) -> Void
    ) {
        self.source = source
        self.columns = columns
        self.spacing = spacing
        self.accent = accent
        self.card = card
        self.commit = commit
    }

    /// Local mirror so the live hover-reorder is independent of the
    /// SwiftData/CloudKit @Query churn. Reconciled from `source` only while
    /// idle, so an in-flight remote update can't yank the card mid-drag.
    @State private var items: [Note] = []
    @State private var draggingID: UUID?

    private var sourceSignature: String {
        source.map { "\($0.id.uuidString):\($0.order)" }.joined(separator: "|")
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(items) { note in
                cell(note)
            }
        }
        // NOTE: no grid-level catch-all dropDestination — a drop region
        // wrapping the whole grid nests under each cell's own drop region
        // and skews SwiftUI's hover hit-testing (the reorder fired a card
        // late). Each cell handles its own drop; the tiny inter-card gaps
        // are not a realistic drop target.
        // The single animation that makes neighbours glide as the order
        // mutates. LazyVGrid honours an explicit value-keyed spring here.
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: items)
        .onAppear { if items.isEmpty { items = source } }
        .onChange(of: sourceSignature) { _, _ in
            if draggingID == nil { items = source }
        }
    }

    @ViewBuilder
    private func cell(_ note: Note) -> some View {
        let isDragging = draggingID == note.id
        card(note)
            // Collapse the dragged card to a clear GAP (its snapshot is the
            // thing following the cursor). The gap still occupies its slot,
            // so as we reorder, the gap moves and neighbours animate to fill.
            .opacity(isDragging ? 0 : 1)
            .overlay {
                if isDragging {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent(note).opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(accent(note).opacity(0.55),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        )
                }
            }
            // System drag — default drag image is a faithful snapshot of the
            // card, which follows the cursor. Setting `draggingID` as a side
            // effect opens the gap above.
            .onDrag {
                draggingID = note.id
                return NSItemProvider(object: note.id.uuidString as NSString)
            }
            // Hover-reorder: the instant the dragged card's image enters this
            // card's drop area, move it here (animated). This is the live
            // "push the other one aside" the user wanted.
            .dropDestination(for: String.self) { _, _ in
                finishDrop(); return true
            } isTargeted: { hovering in
                if hovering { moveDragged(over: note) }
            }
    }

    private func moveDragged(over target: Note) {
        guard let dragging = draggingID, dragging != target.id,
              let from = items.firstIndex(where: { $0.id == dragging }),
              let to = items.firstIndex(where: { $0.id == target.id }),
              from != to else { return }
        // Canonical `.onMove` semantics: dragging FORWARD (to a later card)
        // inserts AFTER the target (to + 1); dragging BACKWARD inserts before
        // it (to). The earlier "always insert before target" made a card's
        // immediate-next neighbour a no-op, so the first card couldn't be
        // dragged toward the end.
        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
            items.move(fromOffsets: IndexSet(integer: from),
                       toOffset: to > from ? to + 1 : to)
        }
    }

    private func finishDrop() {
        guard let dragging = draggingID,
              let moved = items.first(where: { $0.id == dragging }) else {
            draggingID = nil
            return
        }
        commit(items, moved)
        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
            draggingID = nil
        }
    }
}
