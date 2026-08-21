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
        let view = PassthroughView()
        view.backgroundColor = .clear
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onEnd = onEnd
    }

    /// Drop interactions need `isUserInteractionEnabled`, but this view must
    /// not swallow taps aimed at whatever sits behind it. Refusing to be a
    /// hit-test result keeps touch handling exactly as it was while leaving
    /// the drag-and-drop machinery — which does not route through
    /// `hitTest` — free to deliver session callbacks.
    private final class PassthroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

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
