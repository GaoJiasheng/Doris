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
import UniformTypeIdentifiers
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

    /// Bumped every time the drag shows a sign of life (lift, or the pointer
    /// hovering any cell). The watchdog keys off THIS rather than off
    /// `draggingID`, which is what makes the short timeout below safe.
    @State private var lastDragActivity: Date = .distantPast


    /// How long the drag may show no activity before we treat it as abandoned.
    ///
    /// This used to be 20s keyed on `draggingID`, which is set once at lift and
    /// never changes — so the clock measured "time since the drag started" and
    /// had to be generous enough to cover a slow deliberate drag. The cost was
    /// paid by the failure case: `.onDrag` has no cancellation callback, so a
    /// card released anywhere outside a drop region (the weather card, a
    /// section header, off the edge) sat as an empty dashed hole for a full 20
    /// seconds. That reads as a broken app, and it is trivially easy to trigger
    /// — a horizontal swipe on a pinned card is enough.
    ///
    /// Keying on `lastDragActivity` changes the meaning to "time since the
    /// drag last moved", refreshed from `dropUpdated`, which fires
    /// continuously for as long as the drag is over the catcher — and the
    /// catcher now spans well past the grid, so that is essentially the whole
    /// screen. A live drag therefore keeps the clock pinned no matter how
    /// slowly it moves, and the moment the finger lifts the updates stop.
    ///
    /// That is what lets this be short. It is now only the last resort for a
    /// drag the system cancels outright — a long-press that fired `.onDrag`
    /// without the user meaning to drag — where no drop is delivered
    /// anywhere and nothing else can tell us it ended.
    private var abandonedDragTimeout: Duration { .seconds(0.6) }

    /// UTTypes the drag actually registers. `.onDrag` vends an
    /// `NSItemProvider(object: NSString)`, which publishes the plain-text
    /// identifiers below — so the drop side must ask for those, not for a
    /// `Transferable` type.
    /// (Computed, not a `static let`: this type is generic over the card
    /// view, and generic types can't hold static stored properties.)
    private var dragTypes: [UTType] { [.plainText, .utf8PlainText, .text] }

    private var sourceSignature: String {
        source.map { "\($0.id.uuidString):\($0.order)" }.joined(separator: "|")
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(items) { note in
                cell(note)
            }
        }
        // NOTE: don't WRAP the grid in a drop region — nesting one around the
        // cells skews SwiftUI's hover hit-testing and the reorder fires a card
        // late. The backstop below is in `.background` (behind the cells)
        // precisely to avoid that, while still catching drops the cells miss.
        // The single animation that makes neighbours glide as the order
        // mutates. LazyVGrid honours an explicit value-keyed spring here.
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: items)
        // Backstop for drops that land INSIDE the grid but not on a card —
        // the inter-card gaps, or the empty tail of the last row. Sits behind
        // the cells, so a cell's own drop region still wins the hover; this
        // only catches what would otherwise fall through. Without it the drag
        // state never clears and the card stays a dashed hole.
        .background {
            // Deliberately far larger than the grid. A release that lands on
            // a card is handled by that card; everything else — the weather
            // card above, a section header, the empty space below — had no
            // drop target at all, so the drag could only be ended by the
            // watchdog 2.5s later, which is the blank slot users kept
            // reporting. Stretching the catcher past the grid's own bounds
            // gives those releases somewhere to land.
            //
            // It stays in `.background`, behind the cells, so a card still
            // wins any release that lands on a card.
            Color.clear
                .contentShape(Rectangle())
                .onDrop(of: dragTypes, delegate: GridDropDelegate(
                    onUpdate: { if draggingID != nil { lastDragActivity = Date() } },
                    onPerform: { finishDrop() }
                ))
                .padding(-600)
        }
        // Backstop behind the backstop. iOS now clears the state from the real
        // `sessionDidEnd` above, but macOS has no equivalent hook before
        // macOS 26 (`onDragSessionUpdated` is gated there and this app ships
        // to macOS 14), and a session that somehow never reaches the observer
        // would still strand the card. Keep the watchdog for those.
        .task(id: lastDragActivity) {
            guard draggingID != nil else { return }
            try? await Task.sleep(for: abandonedDragTimeout)
            guard !Task.isCancelled, draggingID != nil else { return }
withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                draggingID = nil
                items = source          // discard any half-finished reorder
            }
        }
        .onAppear { if items.isEmpty { items = source } }
        .onDisappear { draggingID = nil }
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
                lastDragActivity = Date()
                return NSItemProvider(object: note.id.uuidString as NSString)
            }
            // Hover-reorder: the instant the dragged card's image enters this
            // card's drop area, move it here (animated). This is the live
            // "push the other one aside" the user wanted.
            .onDrop(of: dragTypes, delegate: GridDropDelegate(
                onEnter: { moveDragged(over: note) },
                onUpdate: { if draggingID != nil { lastDragActivity = Date() } },
                onPerform: { finishDrop() }
            ))
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
        // No animation here, deliberately. The moved card has been sitting
        // at `.opacity(0)` behind its dashed placeholder since the lift; the
        // system has just finished flying the drag preview into that slot.
        // Springing opacity back to 1 from here adds ~300ms of fade on top
        // of the system's own ~400ms drop animation — and with the watchdog
        // no longer masking everything, that fade reads as the card going
        // blank after a successful drop. Snap it back instead.
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { draggingID = nil }
    }
}

/// Bridges the drop side back onto the same generation of API the drag side
/// uses.
///
/// The grid previously paired `.onDrag { NSItemProvider(...) }` with
/// `.dropDestination(for: String.self)`. Those belong to different
/// generations: `dropDestination` decodes through `Transferable`, while
/// `onDrag` vends a hand-registered `NSItemProvider`. Hovering still worked —
/// `isTargeted` only matches type identifiers, which is why the live reorder
/// looked healthy — but the drop itself never decoded, so the perform action
/// never ran. On device the trace showed only LIFT and WATCHDOG: every drag,
/// successful or not, was being ended 2.5 seconds later by the timeout, and
/// the card sat as an empty dashed slot until then.
///
/// `DropDelegate` is the matching counterpart to `.onDrag`, and it hands us
/// both halves we need: `dropEntered` for the live reorder and `performDrop`
/// for the commit.
private struct GridDropDelegate: DropDelegate {
    var onEnter: (() -> Void)? = nil
    /// Called continuously while the drag is over this region — unlike
    /// `dropEntered`, which fires once. It is the closest thing to a
    /// "the drag is still alive" heartbeat SwiftUI offers.
    var onUpdate: (() -> Void)? = nil
    var onPerform: () -> Void

    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) { onEnter?() }

    /// Required for `performDrop` to ever be called.
    ///
    /// Without it SwiftUI supplies a default proposal, and on device that
    /// default refuses the drop: `validateDrop` returned true and
    /// `dropEntered` fired — the live reorder proved the type match was
    /// fine all along — yet `performDrop` never ran, so every drag was left
    /// to the 2.5s watchdog. Stating `.move` explicitly is what makes the
    /// release actually land.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        onUpdate?()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool { onPerform(); return true }
}
