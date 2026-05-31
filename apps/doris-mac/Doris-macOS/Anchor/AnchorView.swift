import SwiftUI
import SwiftData
import DorisCore
import DorisIPC
import DorisMacChrome
import DorisUI

struct AnchorView: View {
    @ObservedObject var model: AnchorModel
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var theme = ThemeSettings.shared
    /// Lifted up from `AnchorNotesView` so the parent can hide the
    /// brand row + tab bar when editing is active — the editor gets
    /// the full right-pane height for itself.
    @State private var editingNote: Note?
    let position: AnchorPosition
    /// True when the screen the anchor lives on has a real camera notch. Drives whether
    /// the idle visual is a small circle (next to the real notch) or a fake-notch pill.
    /// Passed in by AnchorController so it tracks the same screen as the panel itself.
    let screenHasNotch: Bool
    let onTapIdle: () -> Void
    let onTapMessage: (AnchorMessage) -> Void
    let onDismissMessage: (AnchorMessage) -> Void
    let onCloseExpanded: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                idleView
            case .banner(let m):
                expandedMessageView(m)
                    .transition(Self.notchDropTransition)
            case .fix(let m):
                expandedMessageView(m)
                    .transition(Self.notchDropTransition)
            case .expanded:
                // Scale content via `.dorisZoom()`. The panel window
                // itself stays at the size the user dragged it to —
                // resizing the window only changes layout space
                // (more content visible), not font size. Cmd-+ / Cmd-−
                // are what changes font size.
                expandedSummaryView
                    .dorisZoom()
                    .transition(Self.notchDropTransition)
            }
        }
        // No state-change animation. Combined with the `.identity`
        // notch-drop transition, cards snap on and snap off — no
        // mixing fade where backdrop / text colors blend with the
        // menu bar behind the card.
        .animation(nil, value: model.state)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { v in onDragChanged(v.translation) }
                .onEnded { v in onDragEnded(v.translation) }
        )
        // Pin the SwiftUI color-scheme environment to Doris's in-app
        // ThemeSettings for *every* anchor state — banner, fix, idle,
        // expanded. Without this hoist the modifier only covered the
        // expanded panel, so banner / fix cards rendered with whatever
        // the *system* appearance was. If the user had set Doris to
        // dark mode but their Mac was in light mode, the notification
        // backdrop (`CyberPalette.backdrop`) picked the cream variant
        // and the card came out looking light, even though everything
        // else in the app was dark.
        .preferredColorScheme(theme.mode.colorScheme)
    }

    /// Translate the dropdown's avatar state into a HeroMood for the
    /// shared `AvatarHero` view. `.click` maps to a one-shot greeting
    /// bounce, `.notify` to the alert head-shake.
    private func heroMood(for state: AvatarState) -> HeroMood {
        switch state {
        case .idle:     return .idle
        case .click:    return .greeting
        case .notify:   return .alerted
        case .expanded: return .idle
        }
    }

    private var rendersAsFakeNotch: Bool {
        // Fake-notch pill on a screen that doesn't have a real notch (and the user picked
        // the auto/notchAdjacent position) or when explicitly anchored at top center.
        switch position {
        case .notchAdjacent: return !screenHasNotch
        case .topCenter:     return true
        default:             return false
        }
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleView: some View {
        if rendersAsFakeNotch {
            fakeNotchIdle
        } else {
            circleIdle
        }
    }

    private var circleIdle: some View {
        Button {
            model.flashClickReaction()
            onTapIdle()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.88))
                    .overlay(Circle().stroke(.primary.opacity(0.08), lineWidth: 0.5))
                AnchorAvatarView(state: model.avatarState, size: 18)
            }
            .frame(width: AnchorPanelLayout.circleIdleSize, height: AnchorPanelLayout.circleIdleSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(model.hovered ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: model.hovered)
        .onHover { model.hovered = $0 }
        .help("Doris")
    }

    private var fakeNotchIdle: some View {
        Button {
            model.flashClickReaction()
            onTapIdle()
        } label: {
            ZStack {
                FakeNotchShape()
                    .fill(Color.black)
                AnchorAvatarView(state: model.avatarState, size: 16)
                    .padding(.bottom, 4)
            }
            .frame(width: AnchorPanelLayout.pillIdleWidth, height: AnchorPanelLayout.pillIdleHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { model.hovered = $0 }
        .help("Doris")
    }

    // MARK: - Expanded message (banner / fix)

    private func expandedMessageView(_ m: AnchorMessage) -> some View {
        let useFakeNotch = rendersAsFakeNotch
        let levelTint = EventLevelStyle.color(for: m.level)
        // Theme-adaptive accent strength. The same neonPink / neonCyan
        // tint that pops nicely on the deep-purple dark backdrop gets
        // washed out by the cream light backdrop, so light mode bumps
        // both the radial wash opacity and the stroke opacity ~50%
        // higher. Drop shadow is also light-only — dark mode doesn't
        // need elevation cues because the card is already much darker
        // than whatever sits behind it.
        let isLight = theme.mode == .light
        let washPeakAlpha: Double = isLight ? 0.30 : 0.20
        let washMidAlpha: Double  = isLight ? 0.08 : 0.05
        let strokeAlphaBase: Double = isLight ? 0.70 : 0.55
        let levelIntensity = EventLevelStyle.intensity(for: m.level)
        let cardWidth = m.displayMode == .fix ? AnchorPanelLayout.fixWidth : AnchorPanelLayout.bannerWidth
        let cardHeight = m.displayMode == .fix ? AnchorPanelLayout.fixHeight : AnchorPanelLayout.bannerHeight

        // Card chrome tuned for the halved 42pt banner / 54pt fix
        // height. Avatar shrinks 36 → 22pt, title font 15 → 13pt,
        // padding 14 → 5pt top/bottom. fix mode keeps a 1-line body
        // squeezed in below the title; banner mode drops the body
        // entirely — there's literally no room for two lines of text.
        return HStack(alignment: .center, spacing: 10) {
            AnchorAvatarView(state: model.avatarState, size: 20)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    // Tiny level glyph next to the title — only when
                    // the level is louder than info, so routine peeks
                    // don't get visually noisy.
                    if m.level != .info {
                        Image(systemName: m.level.sfSymbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(levelTint)
                    }
                    Text(m.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                // Body only on fix-mode (sticky critical events) where
                // the extra 12pt of card height makes room for it.
                // Auto-dismiss banners suppress body — at 42pt there's
                // no room and the title carries the message.
                if m.displayMode == .fix, let body = m.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.72))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // X button only on critical / fix — banners auto-dismiss
            // so the X is dead weight, and pulling it out gives the
            // info pill a noticeably cleaner shape.
            if m.displayMode == .fix {
                Button {
                    onDismissMessage(m)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.6))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, useFakeNotch ? 4 : 5)
        .padding(.bottom, 5)
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
        .background(backgroundShape(useFakeNotch: useFakeNotch))
        // Soft level-tinted outline so the severity is legible at a
        // glance even with the title cropped. Info gets a barely-there
        // line; reminder/critical pop a bit more. Opacity comes from
        // the shared `intensity(for:)` helper so the dim-info / full-
        // brightness split stays in sync with the countdown stripe and
        // the event-list leading rule (one knob, three call sites).
        // Per-level static radial-gradient wash from the top of the
        // card — every level gets one, only the hue and intensity
        // change. Without this overlay info / reminder showed the
        // raw `CyberPalette.backdrop` linear gradient (deep purple →
        // near-black in dark mode) which read as the card backdrop
        // visibly changing color top-to-bottom, while critical's
        // existing pink wash masked the same gradient and looked
        // static. Painting a level-tinted wash everywhere gives all
        // three levels the same "static colored panel" identity, with
        // hierarchy encoded by hue (pink for critical, cyan for the
        // others) and by `intensity` (info dimmed).
        .overlay {
            Self.notchDropShape()
                .fill(
                    RadialGradient(
                        colors: [
                            levelTint.opacity(washPeakAlpha * levelIntensity),
                            levelTint.opacity(washMidAlpha * levelIntensity),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 0,
                        endRadius: cardWidth * 0.7
                    )
                )
                .allowsHitTesting(false)
        }
        .overlay(
            Group {
                if m.level == .critical {
                    // Critical keeps its pink→cyan gradient stroke;
                    // pink dominant in both themes, but light mode
                    // shifts the stops up a touch so the stroke
                    // doesn't get lost against the cream backdrop.
                    Self.notchDropShape()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    CyberPalette.neonPink.opacity(isLight ? 0.95 : 0.85),
                                    CyberPalette.neonPink.opacity(isLight ? 0.70 : 0.55),
                                    CyberPalette.neonCyan.opacity(isLight ? 0.50 : 0.35)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                        .padding(0.5)
                } else {
                    Self.notchDropShape()
                        .stroke(
                            levelTint.opacity(strokeAlphaBase * levelIntensity),
                            lineWidth: 0.8
                        )
                        .padding(0.5)
                }
            }
        )
        // Countdown stripe — only on auto-dismiss banners. Lives at
        // the bottom edge, runs from full width to zero in linear
        // time over `level.bannerDuration`. Anchored at the leading
        // edge so the visual reads as "time remaining," depleting
        // toward the right. Placed BEFORE the clipShape below so the
        // stripe's left/right ends get rounded along with the card —
        // otherwise the stripe rectangle pokes past the corner radius
        // on both sides.
        .overlay(alignment: .bottomLeading) {
            if m.displayMode == .banner {
                // Stripe contrast is set explicitly per level (rather
                // than reusing `EventLevelStyle.intensity`) so the
                // hierarchy reads loud:
                //   - info (1.5s): visible-but-soft stripe so the user
                //     still sees the countdown without it competing
                //     with the message text.
                //   - reminder (4s): high-contrast stripe — this is the
                //     "I'll be here a while" cue, so the bar deserves
                //     to be obvious.
                // Light mode bumps both ranges because the cream
                // backdrop swallows neon at the dark-mode opacity
                // levels.
                let (leadAlpha, peakAlpha): (Double, Double) = {
                    switch m.level {
                    case .info:
                        return isLight ? (0.32, 0.55) : (0.20, 0.38)
                    case .reminder:
                        return isLight ? (0.60, 0.90) : (0.48, 0.80)
                    case .critical:
                        return (0, 0) // never shown — critical is .fix
                    }
                }()
                CountdownStripe(
                    width: cardWidth,
                    duration: m.level.bannerDuration,
                    color: levelTint,
                    leadingAlpha: leadAlpha,
                    trailingAlpha: peakAlpha,
                    messageID: m.id
                )
            }
        }
        // Clip everything (background, washes, border, stripe) to the
        // notch-drop silhouette so no overlay leaks past the rounded
        // corners. Shadow is applied AFTER the clip so it projects
        // from the rounded silhouette, not from the bounding box.
        .clipShape(Self.notchDropShape())
        // Light-mode elevation: a soft drop shadow lifts the card off
        // the cream backdrop. Dark mode skips this because the card is
        // already much darker than the desktop / menu bar behind it,
        // so a shadow there just adds noise.
        .shadow(
            color: isLight ? Color.black.opacity(0.10) : Color.clear,
            radius: 12, x: 0, y: 4
        )
        .contentShape(Rectangle())
        .onTapGesture { onTapMessage(m) }
    }

    // MARK: - Expanded summary (click → big panel with character on left, content on right)

    private var expandedSummaryView: some View {
        let useFakeNotch = rendersAsFakeNotch
        return HStack(spacing: 0) {
            // LEFT: same cyber-girl hero used in the main window's sidebar,
            // here stretched to 200pt with the right corners flat (the
            // panel's outer border draws the chrome). selfChrome=false to
            // skip its built-in rounded clip so our UnevenRoundedRectangle
            // is the only clip.
            AvatarHero(
                mood: heroMood(for: model.avatarState),
                showWeather: true,
                selfChrome: false
            )
            .frame(width: 200)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )

            // Vertical divider with a neon accent
            Rectangle()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.30, blue: 0.75).opacity(0.0),
                        Color(red: 1.0, green: 0.30, blue: 0.75).opacity(0.6),
                        Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.6),
                        Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 1)

            // RIGHT: header + tabs + content. When the user is editing
            // a note, hide the brand row + tab bar + divider so the
            // inline editor gets every pixel of vertical space — that's
            // what they're focused on at that moment.
            VStack(spacing: 0) {
                if editingNote == nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Brand gradient — adaptive endpoints. Dark mode uses
                    // pale pink → pale cyan to pop against the deep
                    // purple backdrop. Light mode uses saturated
                    // neonPink → neonCyan so the letters still read on
                    // the cream backdrop (the pale variants washed out
                    // to near-invisible there).
                    Text("DORIS")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .kerning(2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(light: CyberPalette.neonPink,
                                          dark: Color(red: 1.0, green: 0.85, blue: 1.0)),
                                    Color(light: CyberPalette.neonCyan,
                                          dark: Color(red: 0.6, green: 1.0, blue: 1.0))
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    Text(L("cyber helper", "赛博助手"))
                        .font(.caption2.monospaced())
                        // Same adaptive trick — saturated cyan in light
                        // mode (full opacity), pale-cyan-with-alpha in
                        // dark mode for the subdued subtitle look.
                        .foregroundStyle(
                            Color(light: CyberPalette.neonCyan.opacity(0.95),
                                  dark: CyberPalette.neonCyan.opacity(0.7))
                        )
                    Spacer()
                    // Theme toggle moved to Settings; the panel auto-
                    // dismisses on outside clicks, so no X button either.
                }
                .padding(.horizontal, 14)
                .padding(.top, useFakeNotch ? 12 : 16)
                .padding(.bottom, 10)

                // Tabs — Today first (mirrors main window's order).
                // Trailing date stamp is permanently parked here as a
                // global "when am I?" anchor (mac main window does the
                // same). Saves the popup a row of scroll content.
                HStack(spacing: 6) {
                    tabButton(L("Today", "今日"), tag: .today)
                    tabButton(L("TODO", "TODO"), tag: .notes)
                    tabButton(L("Events", "事件"), tag: .events)
                    Spacer()
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                Rectangle()
                    .fill(.primary.opacity(0.08))
                    .frame(height: 1)
                } // end `if editingNote == nil` — chrome only when not editing

                // Body
                Group {
                    switch model.expandedTab {
                    case .today:  AnchorTodayView(editing: $editingNote)
                    case .events: AnchorEventsView()
                    case .notes:  AnchorNotesView(editing: $editingNote)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Fill whatever the NSPanel gives us — the panel's size is
        // now user-resizable (drag the bottom-right corner) and the
        // saved size is persisted in `AnchorScreenStore`, so the
        // SwiftUI content shouldn't hard-code the baseline 560×380.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panelBackground(useFakeNotch: useFakeNotch))
        .overlay(panelBorder)
        // Resize is now handled at the NSPanel level via the
        // `.resizable` styleMask + an `NSWindowDelegate` hook in
        // `AnchorController` — drag any edge to resize, no custom
        // SwiftUI handle needed.
        .preferredColorScheme(theme.mode.colorScheme)
    }

    private var panelBorder: some View {
        Self.notchDropShape()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.30, blue: 0.75).opacity(0.35),
                        Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.35)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private func panelBackground(useFakeNotch: Bool) -> some View {
        // Same flat-top / rounded-bottom shape whether or not the
        // display has a real notch — the panel always reads as
        // "hanging from the menu bar," and with `gap = 0` in
        // `computeRect` it sits flush against the notch / fake-notch
        // pill / avatar window above.
        Self.notchDropShape()
            .fill(CyberPalette.backdrop)
    }

    /// Fully-rounded shape used by the panel chrome (the banner card,
    /// the fix card, the expanded summary). Earlier this was a flat-
    /// top / rounded-bottom shape ("hanging from the notch"), but
    /// because the panel is much wider than the actual notch, the
    /// flat top read as a slab with sharp 90° corners poking out
    /// either side. Rounded on all four corners feels softer and is
    /// the original visual identity the user wanted preserved. The
    /// `gap = 0` in `AnchorController.computeRect` keeps the panel
    /// snug against the menu bar so the "from the notch" feel still
    /// holds via proximity rather than geometric merging.
    // Bumped down from 22 → 10 — at the halved 42pt banner height the
    // old 22pt radius made the card almost pill-shaped, eating into
    // the title's horizontal space. 10 keeps it visibly rounded but
    // overall reads as a rectangle.
    static func notchDropShape(cornerRadius: CGFloat = 10) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: cornerRadius,
            style: .continuous
        )
    }

    /// Card enter / exit transition. Set to `.identity` (instant
    /// snap-on / snap-off) — no fade, no scale. Earlier this was a
    /// pure opacity fade, but during the half-transparent frames the
    /// card visibly mixed with whatever sat behind it (menu bar,
    /// desktop) and the perceived backdrop / text colors shifted.
    /// Critical (sticky) hid this from view because its entry fade
    /// settled fast and there was no exit fade; short-lived info /
    /// reminder banners chained appear-fade → stable → disappear-fade
    /// in close enough succession that the color blend read as the
    /// card "breathing colors." Instant transitions kill the blend.
    static let notchDropTransition: AnyTransition = .identity

    private func tabButton(_ label: String, tag: AnchorModel.Tab) -> some View {
        let isSelected = model.expandedTab == tag
        return Button {
            model.expandedTab = tag
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                .kerning(0.5)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.45)))
                // Lock natural width so a crowded row (esp. at higher
                // zoom levels) doesn't compress labels into vertical
                // one-character stacks.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.15)
                              : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected
                            ? Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.5)
                            : Color.clear,
                            lineWidth: 0.5
                        )
                )
                // Make the full padded capsule hit-testable; otherwise
                // unselected tabs (Color.clear background) only register
                // clicks on the text glyphs themselves.
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func backgroundShape(useFakeNotch _: Bool) -> some View {
        // Same flat-top / rounded-bottom shape as the expanded panel,
        // regardless of whether there's a real notch on this display.
        // See `notchDropShape` for why both paths share one shape.
        Self.notchDropShape().fill(CyberPalette.backdrop)
    }
}

// MARK: - Banner countdown stripe

/// Thin horizontal stripe pinned to the bottom of an auto-dismiss
/// banner card. Width animates linearly from full → zero over the
/// banner's lifetime, giving the user a visual sense of how much time
/// they have left before it disappears.
///
/// `messageID` is the trigger — when it changes (a new banner arrives
/// while one is still on screen), the `@State` resets and the
/// animation restarts. Without keying on the id, the stripe would
/// inherit the previous animation and look broken.
private struct CountdownStripe: View {
    let width: CGFloat
    let duration: TimeInterval
    let color: Color
    /// Alpha at the bar's leading edge (left tip). Pair with
    /// `trailingAlpha` to control the gradient's contrast band — the
    /// caller picks values that match each level's desired loudness
    /// (info: soft, reminder: prominent) and the current theme.
    let leadingAlpha: Double
    let trailingAlpha: Double
    let messageID: UUID

    @State private var progress: CGFloat = 1.0

    var body: some View {
        // Solid gradient stripe with no glow shadow — the popup chrome
        // never uses a halo, so layering one here read as foreign.
        // Contrast is tuned by the caller through `leadingAlpha` /
        // `trailingAlpha` rather than a single intensity multiplier,
        // because info and reminder want *different* opacity bands,
        // not the same band scaled.
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [color.opacity(leadingAlpha), color.opacity(trailingAlpha)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: max(0, width * progress), height: 2)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            .onAppear {
                // Reset to full, then animate down. Without the reset
                // (and the messageID keying on `.id`), a second banner
                // arriving back-to-back would start mid-depletion.
                progress = 1.0
                withAnimation(.linear(duration: duration)) {
                    progress = 0
                }
            }
            .id(messageID)
    }
}

// MARK: - Anchor body subviews

private struct AnchorEventsView: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.modelContext) private var ctx

    /// Only today's active events are fetched on appear; older days
    /// roll up into collapsed `DayCollapsibleEventList` sections that
    /// fetch on expand. Anchor popup is the highest-frequency event
    /// surface — keeping its initial paint to "today only" is the
    /// single biggest perf win.
    @Query private var todayMessages: [Message]

    init() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let activeRaw = MessageState.active.rawValue
        _todayMessages = Query(
            filter: #Predicate<Message> { msg in
                msg.receivedAt >= startOfToday && msg.stateRaw == activeRaw
            },
            sort: [SortDescriptor(\Message.receivedAt, order: .reverse)]
        )
    }

    var body: some View {
        if todayMessages.isEmpty && !hasAnyMessage {
            empty(L("No events yet", "暂无事件"), systemImage: "bell.slash")
        } else {
            ScrollView {
                // Anchor popup is narrow & short — surface a week of
                // past days, deeper history is for the main window
                // Events tab.
                DayCollapsibleEventList(
                    today: todayMessages,
                    pastDayCount: 7,
                    rowSpacing: 4
                ) { m in
                    anchorRow(for: m)
                }
                .padding(8)
            }
        }
    }

    /// Avoids a full-history @Query just to decide between empty-state
    /// vs collapsed-archive UI when today happens to be quiet.
    private var hasAnyMessage: Bool {
        var desc = FetchDescriptor<Message>()
        desc.fetchLimit = 1
        let count = (try? ctx.fetchCount(desc)) ?? 0
        return count > 0
    }

    @ViewBuilder
    private func anchorRow(for m: Message) -> some View {
        let levelTint = EventLevelStyle.color(for: m.level)
        HStack(alignment: .top, spacing: 8) {
            // Severity stripe — full for critical/reminder, dimmed
            // for info via `EventLevelStyle.intensity(for:)` so the
            // popup's two-color palette stays consistent across every
            // event surface.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(levelTint)
                .frame(width: 2.5)
                .opacity(EventLevelStyle.intensity(for: m.level))

            Image(systemName: m.iconName ?? m.source.sfSymbol)
                .foregroundStyle(levelTint.opacity(EventLevelStyle.intensity(for: m.level)))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(m.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if m.level != .info {
                        Image(systemName: m.level.sfSymbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(levelTint)
                    }
                }
                if let body = m.bodyMarkdown, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.6))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Text(m.receivedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.04))
        )
    }
}

private struct AnchorNotesView: View {
    // SwiftData's `SortDescriptor` doesn't accept Bool directly — pull
    // by `updatedAt` and re-sort in `sortedNotes` to put pinned first.
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var notes: [Note]
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var lang = LanguageSettings.shared
    @Binding var editing: Note?
    /// Active vs archived view. Default is `active` — the daily TODO
    /// list. Switching to `archived` shows the squirreled-away rows so
    /// the user can restore mis-archives.
    @State private var filter: TodoFilter = .active

    /// Filter + sort. Three partitions never overlap: a row is in
    /// exactly one of Active / Archived / Trash. Trash takes priority
    /// over Archived (a deleted-then-archived row shows in Trash).
    private var sortedNotes: [Note] {
        let filtered = notes.filter { n in
            switch filter {
            case .trash:    return n.deleted
            case .archived: return !n.deleted && n.archived
            case .active:   return !n.deleted && !n.archived
            }
        }
        switch filter {
        case .trash:
            return filtered.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        case .archived:
            return filtered.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        case .active:
            return filtered.sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                if lhs.done != rhs.done     { return !lhs.done && rhs.done }
                if lhs.order != rhs.order   { return lhs.order < rhs.order }
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    /// Reorder: place `draggedID` right before `targetID`. Renumbers
    /// every visible row's `order` field with monotonically increasing
    /// integers so we never hit the "averaging two equal orders gives
    /// the same order" collision (which happens with legacy rows that
    /// all have order 0). O(N) save per drag, fine for normal list
    /// sizes.
    private func moveDraggedBefore(_ targetID: UUID, dragged draggedID: UUID) {
        let visible = sortedNotes
        guard visible.contains(where: { $0.id == targetID }),
              let dragged = visible.first(where: { $0.id == draggedID }) else { return }
        var reordered = visible.filter { $0.id != draggedID }
        let insertIdx = reordered.firstIndex(where: { $0.id == targetID }) ?? 0
        reordered.insert(dragged, at: insertIdx)
        for (i, n) in reordered.enumerated() {
            n.order = Double(i)
        }
        dragged.updatedAt = Date()
        try? ctx.save()
    }
    private var doneActiveCount: Int {
        notes.filter { !$0.deleted && !$0.archived && $0.done }.count
    }
    private var trashCount: Int {
        notes.filter { $0.deleted }.count
    }
    @State private var confirmingEmptyTrash = false

    private var emptyTitle: String {
        switch filter {
        case .active:   return L("No tasks yet",       "暂无任务")
        case .archived: return L("No archived tasks",  "暂无归档任务")
        case .trash:    return L("Trash is empty",     "回收站为空")
        }
    }
    private var emptyIcon: String {
        switch filter {
        case .active:   return "checklist"
        case .archived: return "archivebox"
        case .trash:    return "trash"
        }
    }

    var body: some View {
        Group {
            if let editing {
                InlineNoteEditor(note: editing) {
                    self.editing = nil
                }
            } else {
                listBody
            }
        }
    }

    @FocusState private var focusedNoteID: UUID?

    private var listBody: some View {
        VStack(spacing: 0) {
            // Filter chips — Active vs Archived. Always visible so the
            // user has an obvious entry into the archive view (and out
            // of it).
            filterBar
                .padding(.horizontal, 8)
                .padding(.top, 6)
            if sortedNotes.isEmpty {
                empty(emptyTitle, systemImage: emptyIcon)
                    .padding(.top, 30)
                if filter == .active {
                    addQuickButton
                        .padding(.top, 8)
                }
            } else {
                ScrollView {
                    // spacing: 0 so adjacent TODO rows touch — no
                    // dead non-clickable strip between them. The row's
                    // own internal padding gives each one comfortable
                    // height to click into.
                    VStack(spacing: 0) {
                        ForEach(sortedNotes.prefix(50)) { n in
                            TodoRow(
                                note: n,
                                focused: $focusedNoteID,
                                onSubmit: { addNoteAfter(n) },
                                onExpand: { editing = n },
                                onDropBefore: { dragged in
                                    moveDraggedBefore(n.id, dragged: dragged)
                                }
                            )
                        }
                        if filter == .active {
                            addQuickButton
                                .padding(.top, 8)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    /// Three-chip filter switch (Active / Archived / Trash) with a
    /// context-sensitive bulk action on the right:
    ///   - Active view + done items → "归档已完成 (N)"
    ///   - Trash view + items present → "清空 (N)" (with confirmation)
    private var filterBar: some View {
        HStack(spacing: 6) {
            filterChip(.active,   label: L("Active",   "未归档"), icon: "checklist")
            filterChip(.archived, label: L("Archived", "已归档"), icon: "archivebox")
            filterChip(.trash,    label: L("Trash",    "回收站"), icon: "trash")
            Spacer()
            bulkAction
        }
        .alert(L("Empty trash?", "清空回收站?"), isPresented: $confirmingEmptyTrash) {
            Button(L("Empty (\(trashCount))", "清空 (\(trashCount))"), role: .destructive) {
                emptyTrash()
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("Items in the trash will be permanently deleted and can't be recovered.",
                   "回收站中的任务将被彻底删除,无法恢复。"))
        }
    }

    @ViewBuilder
    private var bulkAction: some View {
        if filter == .active && doneActiveCount > 0 {
            bulkButton(
                icon: "tray.full",
                label: L("Archive done (\(doneActiveCount))",
                         "归档已完成 (\(doneActiveCount))"),
                tint: CyberPalette.neonCyan,
                help: L("Move all completed tasks to archive",
                        "把所有已完成任务移到归档")
            ) { archiveAllDone() }
        } else if filter == .trash && trashCount > 0 {
            bulkButton(
                icon: "trash.slash",
                label: L("Empty (\(trashCount))", "清空 (\(trashCount))"),
                tint: CyberPalette.neonPink,
                help: L("Permanently delete every item in trash",
                        "彻底删除回收站中所有任务")
            ) { confirmingEmptyTrash = true }
        }
    }

    private func bulkButton(icon: String, label: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.1)))
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func filterChip(_ value: TodoFilter, label: String, icon: String) -> some View {
        let selected = (filter == value)
        return Button { filter = value } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(selected ? .semibold : .regular))
            }
            .foregroundStyle(selected
                             ? Color.primary
                             : Color.primary.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(selected
                               ? Color.primary.opacity(0.10)
                               : Color.clear)
            )
            .overlay(
                Capsule().stroke(selected
                                 ? Color.primary.opacity(0.20)
                                 : Color.primary.opacity(0.10),
                                 lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// Bulk archive: stamps every active+done note as archived in one
    /// pass. The morning-routine workflow: yesterday's done tasks all
    /// disappear with one click; undone ones stay.
    private func archiveAllDone() {
        let now = Date()
        for n in notes where !n.deleted && !n.archived && n.done {
            n.archived = true
            n.archivedAt = now
            n.updatedAt = now
        }
        try? ctx.save()
    }

    /// Permanently delete every row currently in the trash. Confirmed
    /// before reaching this — the alert lives in `filterBar`.
    ///
    /// Uses the same "queue-for-purge" pattern as the main window: drop
    /// `updatedAt` and `deletedAt` to 31 days ago so the next
    /// `SyncTimer.purgeTombstones` cycle (≤60 s) hard-deletes them.
    /// Direct `ctx.delete` races against the other device's CloudKit
    /// mirror upload of its still-local copy, which resurrects the
    /// rows on the cloud and they come back on this device. Soft-stamp
    /// + 60 s purge gives the deleted=true flag time to propagate to
    /// every device first.
    private func emptyTrash() {
        let purgeMarker = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        for n in notes where n.deleted {
            n.deletedAt = purgeMarker
            n.updatedAt = purgeMarker
        }
        try? ctx.save()
    }

    /// Compact pill-button — used to be a full-width row that the user
    /// said looked like an unnecessary "new task" entry. Now it reads
    /// as just a button at the bottom of the list.
    private var addQuickButton: some View {
        HStack {
            Button {
                addNoteAfter(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(L("Add task", "新增任务"))
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(CyberPalette.neonCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(CyberPalette.neonCyan.opacity(0.10))
                )
                .overlay(
                    Capsule().stroke(CyberPalette.neonCyan.opacity(0.35), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 10)
    }

    /// Insert a new empty TODO and immediately focus its title field.
    /// Position depends on the anchor:
    ///   - `previous` non-nil → place right AFTER `previous` in the
    ///     visible list. Done by setting `createdAt` to a hair past
    ///     the previous row's `createdAt` (the sort uses createdAt
    ///     ASC, so this lands the new row in the next slot).
    ///   - `previous` nil → place at the very BOTTOM. Done by
    ///     bumping past the largest existing `createdAt`.
    private func addNoteAfter(_ previous: Note?) {
        let n = Note(title: "")
        let stamp: Date
        if let previous {
            stamp = previous.createdAt.addingTimeInterval(0.001)
        } else {
            let maxCreated = notes.map(\.createdAt).max() ?? Date()
            stamp = maxCreated.addingTimeInterval(1)
        }
        n.createdAt = stamp
        n.updatedAt = stamp
        ctx.insert(n)
        try? ctx.save()
        // Focus the new row so the user can type immediately.
        DispatchQueue.main.async {
            focusedNoteID = n.id
        }
    }
}

// (TodoRow lives in DorisUI — the same row UI is used by both this
// dropdown view and the main window's notes pane.)

// MARK: - Today tab (pinned + upcoming, shared design w/ mac main window)
//
// Uses the same `TodayPinnedCard` / `TodayCalendarRow` from
// DorisUI/Today/TodayComponents.swift as the mac main window's Today
// pane and the iOS Today screen, so visual tweaks live in one place.
// No weather card here — the avatar window hanging above this panel
// already shows weather, like the main window's sidebar does.
//
// `editing` is bound from the parent `AnchorView.editingNote` so the
// chrome (title bar + tabs) hides while a note is open, matching the
// behavior of the popup's TODO tab.

private struct AnchorTodayView: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.modelContext) private var ctx

    @Query(
        filter: #Predicate<Note> { note in !note.archived && !note.deleted },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var allNotes: [Note]

    @Binding var editing: Note?

    private var pinnedNotes: [Note] {
        allNotes
            .filter { $0.pinned }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (l?, r?): return l < r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return a.updatedAt > b.updatedAt
                }
            }
    }

    /// Mirrors `MainTodayView.calendarNotes`: drop past + completed
    /// rows so the popup's Today tab doesn't carry yesterday's
    /// finished work. Overdue (past + not done) stays visible — the
    /// popup is the highest-frequency surface and the user needs to
    /// see what's still on their plate.
    private var calendarNotes: [Note] {
        allNotes
            .filter { $0.dueDate != nil && !$0.isPastAndCompleted() }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        // Same pattern as `AnchorNotesView`: swap the whole body to the
        // inline editor when a note is opened. The parent panel hides
        // its title bar + tab strip in the same condition (because
        // `editingNote != nil`), so the editor occupies the full popup.
        Group {
            if let editing {
                InlineNoteEditor(note: editing) {
                    self.editing = nil
                }
            } else {
                scrollBody
            }
        }
    }

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Date stamp lives up in `AnchorView.chrome`'s tab row
                // (next to the trailing Spacer, only when Today is the
                // active tab). Saves a line of vertical space inside
                // the popup, which is short.

                if !pinnedNotes.isEmpty {
                    // See `MainTodayView` — pinned gets the warm pink
                    // (user-flagged / attention) and upcoming gets the
                    // calmer cyan (scheduled), opposite of the original.
                    sectionHeader(
                        icon: "pin.fill",
                        title: L("Pinned", "置顶"),
                        tint: CyberPalette.neonPink
                    )
                    // Bumped from 150 → 225 (+50%) to match the main
                    // window's wider pinned cards. At default popup
                    // size (~330pt content) this lands 1 column;
                    // user-resized wider popups fan out to 2.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 225), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(pinnedNotes) { n in
                            Button { editing = n } label: {
                                TodayPinnedCard(note: n)
                            }
                            .buttonStyle(.plain)
                            .noteContextMenu(for: n, onOpenEditor: { editing = n })
                        }
                    }
                }

                if !calendarNotes.isEmpty {
                    sectionHeader(
                        icon: "calendar",
                        title: L("Upcoming", "日程"),
                        tint: CyberPalette.neonCyan
                    )
                    VStack(spacing: 6) {
                        ForEach(calendarNotes) { n in
                            Button { editing = n } label: {
                                TodayCalendarRow(note: n)
                            }
                            .buttonStyle(.plain)
                            .noteContextMenu(for: n, onOpenEditor: { editing = n })
                        }
                    }
                }

                if pinnedNotes.isEmpty && calendarNotes.isEmpty {
                    emptyState
                }
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
    }

    private func sectionHeader(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .kerning(2)
            Rectangle()
                .fill(tint.opacity(0.18))
                .frame(height: 0.6)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(CyberPalette.neonCyan.opacity(0.45))
            Text(L("All clear", "今日清净"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.65))
            Text(L("Pin a note or set a due date to see it here.",
                   "置顶笔记或设定截止日期即可出现在这里。"))
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

@ViewBuilder
private func empty(_ title: String, systemImage: String, subtitle: String? = nil) -> some View {
    VStack(spacing: 6) {
        Spacer()
        Image(systemName: systemImage)
            .font(.system(size: 28))
            .foregroundStyle(.primary.opacity(0.4))
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.primary.opacity(0.6))
        if let subtitle {
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        Spacer()
    }
    .frame(maxWidth: .infinity)
}

// MARK: - Model

@MainActor
final class AnchorModel: ObservableObject {
    enum Tab { case today, events, notes }
    @Published var state: AnchorState = .idle
    @Published var hovered: Bool = false
    @Published var expandedTab: Tab = .today
    @Published var avatarState: AvatarState = .idle

    private var resetTask: Task<Void, Never>?

    /// Briefly flash the click reaction, then reset to a state appropriate for the
    /// current panel state (idle pill / expanded panel).
    func flashClickReaction() {
        avatarState = .click
        scheduleReset(after: 0.6)
    }

    func flashNotifyReaction() {
        avatarState = .notify
        scheduleReset(after: 0.8)
    }

    private func scheduleReset(after seconds: Double) {
        resetTask?.cancel()
        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            switch self?.state {
            case .expanded: self?.avatarState = .expanded
            default: self?.avatarState = .idle
            }
        }
    }
}

/// Rectangle with rounded BOTTOM corners only — looks like a notch hanging
/// from the top edge of the screen.
struct FakeNotchShape: Shape {
    var cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        p.closeSubpath()
        return p
    }
}
