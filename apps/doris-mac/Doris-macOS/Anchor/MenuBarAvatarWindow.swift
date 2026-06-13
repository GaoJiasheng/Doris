import AppKit
import SwiftUI
import DorisCore
import DorisIPC
import DorisMacChrome
import DorisUI

/// Borderless NSWindow that hosts the avatar at one of four screen edges.
/// On the TOP edge of a notched display it extends the camera notch to the right.
/// On any other edge / on non-notched displays' top, it draws as a small tab whose
/// flat side hugs the screen edge.
/// Drag to move; on release it snaps to the nearest edge of whichever screen the
/// cursor ended on.
@MainActor
final class MenuBarAvatarWindow {
    private let window: NSWindow
    private let model = MenuBarModel()
    private let onClick: () -> Void
    /// Cursor position relative to the window's bottom-left when drag started, in global
    /// screen coords. Using global cursor + this offset avoids the feedback loop you get
    /// when a SwiftUI DragGesture's view-local translation shifts as the window moves.
    private var dragCursorOffset: CGPoint?

    var screenFrame: NSRect { window.frame }
    var screen: NSScreen? { window.screen ?? bestScreen() }
    var edge: AnchorEdge { model.edge }

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 40, height: 32)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        win.isReleasedWhenClosed = false
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.isMovable = false
        win.hidesOnDeactivate = false
        self.window = win

        let m = self.model
        let host = NSHostingController(rootView: MenuBarAvatarContent(
            model: m,
            onClick: onClick,
            onDragChanged: { [weak self] t in self?.dragChanged(t) },
            onDragEnded:   { [weak self] _ in self?.dragEnded() }
        ))
        // Static-content optimisation: tell AppKit it can rasterise the
        // SwiftUI hosting view into a single CALayer and cache that
        // bitmap. Without this the window's `NSDisplayCycleObserver`
        // re-renders the SwiftUI tree on every display refresh (60–120 Hz)
        // even though the content never changes — the dominant CPU cost
        // for an idle Doris.
        host.view.wantsLayer = true
        host.view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        win.contentViewController = host

        relayout()
        win.orderFrontRegardless()
    }

    func hide() { window.orderOut(nil) }

    /// Recompute frame + visual style from the saved screen + edge.
    ///
    /// Also persists the chosen screen back to `AnchorScreenStore` —
    /// after a display hot-plug the previously-saved display ID may
    /// no longer be attached, and `bestScreen()` falls back to the
    /// primary. Writing the fallback back keeps the saved ID in sync
    /// with where the avatar actually is, so the next launch lands
    /// the avatar on the right display instead of going through the
    /// fallback chain again.
    func relayout() {
        guard let s = bestScreen() else { return }
        let edge = AnchorScreenStore.savedEdge()
        model.edge = edge
        let layout = layoutFor(edge: edge, screen: s)
        model.shape = layout.shape
        window.setFrame(layout.frame, display: true)
        AnchorScreenStore.save(screen: s)
    }

    // MARK: - Drag

    private func dragChanged(_ translation: CGSize) {
        // Ignore the SwiftUI translation; sample the global cursor instead. The first
        // call records the cursor's offset within the window so subsequent moves are
        // an absolute repositioning rather than a relative one.
        let mouse = NSEvent.mouseLocation
        if dragCursorOffset == nil {
            dragCursorOffset = CGPoint(
                x: mouse.x - window.frame.origin.x,
                y: mouse.y - window.frame.origin.y
            )
        }
        guard let offset = dragCursorOffset else { return }
        let newOrigin = CGPoint(x: mouse.x - offset.x, y: mouse.y - offset.y)
        window.setFrameOrigin(newOrigin)
    }

    private func dragEnded() {
        dragCursorOffset = nil
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        // No force-unwrap — bail if there are zero screens (impossible
        // in practice, but the `!` would bake this file's source path
        // into runtime trap metadata).
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(center) })
                    ?? window.screen
                    ?? NSScreen.main
                    ?? NSScreen.screens.first else {
            return
        }
        let dTop    = abs(target.frame.maxY - center.y)
        let dBottom = abs(center.y - target.frame.minY)
        let dRight  = abs(target.frame.maxX - center.x)
        let dLeft   = abs(center.x - target.frame.minX)
        // Use `?? .top` instead of `!.0` — the four-element array is
        // always non-empty so `min(by:)` never returns nil in practice,
        // but the force-unwrap embeds this file's source path into
        // runtime trap metadata. The default keeps behavior identical
        // without the path baking.
        let nearest: AnchorEdge = ([
            (AnchorEdge.top, dTop),
            (.bottom, dBottom),
            (.right, dRight),
            (.left, dLeft)
        ].min(by: { $0.1 < $1.1 })?.0) ?? .top

        AnchorScreenStore.save(screen: target)
        AnchorScreenStore.save(edge: nearest)
        relayoutAnimated()
    }

    private func relayoutAnimated() {
        guard let s = bestScreen() else { return }
        let edge = AnchorScreenStore.savedEdge()
        model.edge = edge
        let layout = layoutFor(edge: edge, screen: s)
        model.shape = layout.shape
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(layout.frame, display: true)
        })
    }

    // MARK: - Edge → frame + shape

    private struct Layout { let frame: NSRect; let shape: MenuBarModel.Shape }

    private func layoutFor(edge: AnchorEdge, screen s: NSScreen) -> Layout {
        let f = s.frame
        switch edge {
        case .top:
            // Park to the LEFT of the camera notch instead of the right —
            // the right side of the menu bar is busy with status items
            // (Wi-Fi, battery, Control Center, time, third-party agents)
            // and the avatar would crowd them. Left of the notch is shared
            // only with the frontmost app's menus, which are usually short
            // (File / Edit / View) and rarely reach the notch on a 14"+
            // display.
            //
            // We don't trust `auxiliaryTopLeftArea` for the geometry on
            // every macOS revision (it occasionally returns an unexpected
            // origin offset on multi-display setups). Instead, take its
            // height for the menu-bar strip and compute the notch's left
            // edge ourselves: the notch is centered at `screen.midX`, and
            // its half-width is `(screen.frame.width - rightArea.width -
            // leftArea.width) / 2`. That math reduces cleanly to
            // `notchLeftEdge = leftArea.maxX` IF `leftArea` already starts
            // at the screen's left edge, but defensively we cap to
            // `min(leftArea.maxX, screenMidXishLeftEdge)` so we always
            // place the avatar in the screen's LEFT half.
            if #available(macOS 12.0, *),
               let leftArea = s.auxiliaryTopLeftArea,
               let rightArea = s.auxiliaryTopRightArea,
               s.safeAreaInsets.top > 0 {
                let height = leftArea.height
                let visibleWidth: CGFloat = max(36, height + 4)
                let overshoot: CGFloat = 14
                let width = visibleWidth + overshoot
                // Notch left edge: the right edge of the left-of-notch
                // unobscured area. Both `leftArea.maxX` and
                // `rightArea.minX` should bracket the notch tightly.
                let notchLeftEdge = leftArea.maxX
                let xLeft = notchLeftEdge - visibleWidth
                let yTop = f.maxY

                // Sanity-check the geometry. Right after a hot-plug
                // the window server can deliver a partially-zeroed
                // `auxiliaryTopLeftArea` (height present, maxX small
                // or zero) — without this gate we'd compute a hugely
                // negative `xLeft` and the avatar would land at the
                // top-left corner of the screen. Require both that
                // the avatar is wholly inside the screen and that the
                // notch sits roughly where we expect (right of midX
                // minus a generous margin).
                let avatarFitsOnScreen = xLeft >= f.minX
                    && xLeft + width <= f.maxX + overshoot
                let notchLooksReal = notchLeftEdge >= f.midX - 200
                guard avatarFitsOnScreen && notchLooksReal else {
                    DorisLog.app.notice(
                        """
                        notch-extension geometry suspicious — falling back \
                        to fakeNotch. screen=\(NSStringFromRect(f), privacy: .public) \
                        leftArea=\(NSStringFromRect(leftArea), privacy: .public) \
                        rightArea=\(NSStringFromRect(rightArea), privacy: .public) \
                        computedXLeft=\(xLeft, privacy: .public)
                        """
                    )
                    let fbWidth: CGFloat = 96
                    let fbHeight: CGFloat = 26
                    return Layout(
                        frame: NSRect(x: f.midX - fbWidth / 2, y: f.maxY - fbHeight, width: fbWidth, height: fbHeight),
                        shape: .fakeNotch
                    )
                }

                let frame = NSRect(x: xLeft, y: yTop - height, width: width, height: height)
                DorisLog.app.notice(
                    """
                    notch-extension layout: screen=\(NSStringFromRect(s.frame), privacy: .public) \
                    leftArea=\(NSStringFromRect(leftArea), privacy: .public) \
                    rightArea=\(NSStringFromRect(rightArea), privacy: .public) \
                    avatarFrame=\(NSStringFromRect(frame), privacy: .public)
                    """
                )

                return Layout(frame: frame, shape: .notchExtension)
            } else {
                let width: CGFloat = 96
                let height: CGFloat = 26
                return Layout(
                    frame: NSRect(x: f.midX - width / 2, y: f.maxY - height, width: width, height: height),
                    shape: .fakeNotch
                )
            }
        case .right:
            // Mirror the top/bottom fake-notch proportions (96 along edge × 26 perpendicular)
            // but elongated VERTICALLY so the tab feels as substantial as the horizontal ones.
            let perpendicular: CGFloat = 44
            let alongEdge: CGFloat = 96
            let overshoot: CGFloat = 10
            return Layout(
                frame: NSRect(
                    x: f.maxX - perpendicular + overshoot,
                    y: f.midY - alongEdge / 2,
                    width: perpendicular,
                    height: alongEdge
                ),
                shape: .edgeRight
            )
        case .left:
            let perpendicular: CGFloat = 44
            let alongEdge: CGFloat = 96
            let overshoot: CGFloat = 10
            return Layout(
                frame: NSRect(
                    x: f.minX - overshoot,
                    y: f.midY - alongEdge / 2,
                    width: perpendicular,
                    height: alongEdge
                ),
                shape: .edgeLeft
            )
        case .bottom:
            let height: CGFloat = 26
            let width: CGFloat = 96
            return Layout(
                frame: NSRect(x: f.midX - width / 2, y: f.minY, width: width, height: height),
                shape: .edgeBottom
            )
        }
    }

    private func bestScreen() -> NSScreen? {
        if let saved = AnchorScreenStore.savedScreen() { return saved }
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}

// MARK: - SwiftUI

@MainActor
final class MenuBarModel: ObservableObject {
    enum Shape { case notchExtension, fakeNotch, edgeRight, edgeLeft, edgeBottom }
    @Published var shape: Shape = .notchExtension
    @Published var edge: AnchorEdge = .top
}

private struct MenuBarAvatarContent: View {
    @ObservedObject var model: MenuBarModel
    @ObservedObject var settings = AppearanceSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared
    let onClick: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onClick) {
            ZStack {
                background
                AvatarPortrait()
                    .clipShape(Circle())
                    .frame(width: 26, height: 26)
                    .modifier(AvatarOffsetModifier(shape: model.shape))
            }
            // No `.scaleEffect` + `.animation(value:)` here. SwiftUI keeps
            // a persistent `AnimatorState` alive for any value-bound
            // `.animation` modifier even when nothing is currently
            // animating, and that AnimatorState ticks the display loop
            // at the screen refresh rate. Removing this single modifier
            // dropped idle CPU from ~45 % to flat. The 4 % hover bump
            // wasn't worth a permanently-running render loop.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(L(
            "Doris — drag to a different screen edge · right-click for settings",
            "Doris — 拖动可切换屏幕边缘 · 右键打开设置"
        ))
        .contextMenu {
            Button(L("Open Main Window", "打开主窗口")) {
                AppCommands.openMainWindow()
            }
            Divider()
            Button(L("Sync Now", "立即同步")) {
                AppCommands.syncNow()
            }
            Button(L("Settings…", "设置…")) {
                SettingsWindowController.shared.show()
            }
            Divider()
            Button(L("Quit Doris", "退出 Doris")) {
                NSApp.terminate(nil)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { v in onDragChanged(v.translation) }
                .onEnded   { v in onDragEnded(v.translation) }
        )
    }

    /// Notch-extension always solid black (so it fuses with the real notch).
    /// Every other shape honors the user-set background opacity.
    private var backgroundOpacity: Double {
        model.shape == .notchExtension ? 1.0 : settings.backgroundOpacity
    }

    @ViewBuilder
    private var background: some View {
        let fill = Color.black.opacity(backgroundOpacity)
        switch model.shape {
        case .notchExtension: NotchExtensionShape(cornerRadius: 10).fill(fill)
        case .fakeNotch:      FakeNotchSymmetric(cornerRadius: 10).fill(fill)
        case .edgeRight:      EdgeAttachShape(corner: .right, cornerRadius: 10).fill(fill)
        case .edgeLeft:       EdgeAttachShape(corner: .left, cornerRadius: 10).fill(fill)
        case .edgeBottom:     EdgeAttachShape(corner: .bottom, cornerRadius: 10).fill(fill)
        }
    }
}

private struct AvatarOffsetModifier: ViewModifier {
    let shape: MenuBarModel.Shape
    func body(content: Content) -> some View {
        switch shape {
        // Notch extension now lives LEFT of the notch — the `overshoot`
        // pads the right side (into the notch), so push the avatar LEFT
        // (away from the notch) so it sits cleanly inside the visible
        // tab portion.
        case .notchExtension: content.padding(.trailing, 14)
        case .fakeNotch:      content.padding(.bottom, 2)
        case .edgeRight:      content.padding(.trailing, 10) // shift toward the visible (left) part
        case .edgeLeft:       content.padding(.leading, 10)
        case .edgeBottom:     content.padding(.top, 2)
        }
    }
}

/// Tab that fuses with the LEFT side of the camera notch — the notch
/// itself sits to this rect's right, so the shape's right edge is flat
/// (it disappears into the notch) and the bottom-LEFT corner is the
/// only rounded corner (so the tab eases out of the menu bar smoothly).
struct NotchExtensionShape: Shape {
    var cornerRadius: CGFloat = 10
    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))                                // top-left
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))                             // top-right
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))                             // bottom-right (flat: into the notch)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))                         // along bottom toward left, leaving room for the curve
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))                   // rounded bottom-left
        p.closeSubpath()                                                               // up the left edge to top-left
        return p
    }
}

struct FakeNotchSymmetric: Shape {
    var cornerRadius: CGFloat = 10
    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct EdgeAttachShape: Shape {
    enum Corner { case right, left, bottom }
    var corner: Corner
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        switch corner {
        case .right:
            // Tab attached to the RIGHT edge of the screen: flat right, rounded left corners.
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        case .left:
            // Flat left, rounded right corners.
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        case .bottom:
            // Flat bottom, rounded top corners.
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY))
            p.closeSubpath()
        }
        return p
    }
}

private struct AvatarPortrait: View {
    // Observe the pack store so the menu-bar head swaps live when the user
    // picks a different character in Settings.
    @ObservedObject private var packStore = CharacterPackStore.shared

    var body: some View {
        if let img = packStore.portraitImage() {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Text("K")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.cyan)
        }
    }
}
