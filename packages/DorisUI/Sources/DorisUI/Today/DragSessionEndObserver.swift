#if os(iOS)
import SwiftUI
import UIKit

/// Reports the instant a drag session ends — wherever the finger lifted.
///
/// SwiftUI gives no such callback on iOS. `.onDrag` exposes only `data` and
/// `preview`, and `onDragSessionUpdated`, which does carry a real `.ended`
/// phase, is `@available(iOS, unavailable)` (macOS 26+ only). Without an end
/// event the only way back from an abandoned drag is a timer, and a timer
/// means the dragged card sits as an empty placeholder for however long that
/// timer runs.
///
/// UIKit does report it. Per `UIDropInteraction.h`, `sessionDidEnd` is called
/// "for *every* interaction that ever received `sessionDidEnter`,
/// `sessionDidUpdate`, or `sessionDidExit`" — so an interaction the session
/// merely passed over still hears about the ending, even though the drop
/// happened somewhere else entirely (or nowhere at all).
///
/// This view is therefore an observer, never a destination: it answers
/// `canHandle` with `true` so the session is tracked, then proposes
/// `.cancel` on every update so it can never win a drop away from the cards
/// layered above it.
struct DragSessionEndObserver: UIViewRepresentable {
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEnd: onEnd) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onEnd = onEnd
    }

    // NOTE: an earlier version of this view overrode `hitTest` to return nil,
    // on the assumption that drag-and-drop does not route through hit
    // testing. That assumption was wrong and silently disabled the whole
    // observer: UIKit finds a drop interaction's view by hit testing, and
    // per UIDropInteraction.h only an interaction that received
    // `sessionDidEnter`/`Update`/`Exit` is ever sent `sessionDidEnd`. A view
    // that never wins a hit test receives none of them.
    //
    // The view stays hit-testable. It sits in `.background`, so the cards in
    // front of it win any hit that lands on a card, and it proposes `.cancel`
    // for every session so it can never take a drop that a card should have.

    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var onEnd: () -> Void
        init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

        // Track every session so we are guaranteed the `sessionDidEnd` call.
        func dropInteraction(_ interaction: UIDropInteraction,
                             canHandle session: any UIDropSession) -> Bool { true }

        // ...but never accept anything. `.cancel` leaves the real drop
        // targets above untouched.
        func dropInteraction(_ interaction: UIDropInteraction,
                             sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .cancel)
        }

        func dropInteraction(_ interaction: UIDropInteraction,
                             sessionDidEnd session: any UIDropSession) {
            onEnd()
        }
    }
}
#endif
