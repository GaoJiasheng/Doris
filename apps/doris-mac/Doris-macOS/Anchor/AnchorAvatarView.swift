import SwiftUI
import AppKit
import DorisUI

enum AvatarState: Equatable {
    case idle
    case click
    case notify
    case expanded
}

/// Cyberpunk avatar slot. Falls back to a procedural neon-glyph if no PNG is bundled.
/// State changes drive reaction animations; the underlying art is whatever drops into
/// `apps/doris-mac/Doris-macOS/Resources/Avatar/`.
struct AnchorAvatarView: View {
    let state: AvatarState
    var size: CGFloat = 24

    @State private var clickTrigger: Int = 0

    var body: some View {
        ZStack {
            // Soft neon backdrop glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.25, blue: 0.7).opacity(0.45),
                            Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.20),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.9
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
                // Static glow — previously oscillated 0.6 ↔ 1.0 on a
                // 2.4s `.repeatForever`, which read as a constant
                // "flicker" inside any surface that hosted the avatar
                // (notification cards especially). One fixed alpha
                // keeps the neon halo identity without the motion.
                .opacity(0.7)
                .blur(radius: 4)

            avatarArt
                .scaleEffect(reactionScale)
                .rotationEffect(.degrees(reactionRotation))
                .shadow(color: Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.55), radius: 4)
        }
        .frame(width: size, height: size)
        .onChange(of: state) { _, newState in
            // Only the click reaction still drives a keyframe — it's
            // direct feedback to the user's tap on the avatar and
            // would feel broken if removed. The notify reaction has
            // been retired (see note below) because card-level
            // appearance is already enough of an arrival signal.
            if newState == .click {
                clickTrigger += 1
            }
        }
        // The idle scale/rotation breathing and the glow pulse were
        // both `.repeatForever` animations that read as "always
        // flickering" inside notification cards. They've been folded
        // into static values (`reactionScale = 1.0`, glow alpha pinned
        // to 0.7) so the avatar is calm until the user clicks it.
        // React to click trigger via keyframe animation
        .keyframeAnimator(
            initialValue: ReactionFrame(),
            trigger: clickTrigger
        ) { content, value in
            content
                .scaleEffect(value.scale)
                .rotationEffect(.degrees(value.rotation))
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                LinearKeyframe(1.0, duration: 0)
                SpringKeyframe(1.25, duration: 0.12, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.28, spring: .bouncy)
            }
            KeyframeTrack(\.rotation) {
                LinearKeyframe(0, duration: 0)
                SpringKeyframe(-8, duration: 0.10)
                SpringKeyframe(6, duration: 0.10)
                SpringKeyframe(0, duration: 0.20)
            }
        }
        // Notify keyframe disabled — the head used to bounce
        // (scale 1.0 → 1.4 → 0.95 → 1.0) on each arriving message,
        // which for short-lived banners (info: 1.5s) occupied ~40%
        // of the card's lifetime and read as a flicker. The card
        // appearing is already a strong "arrival" signal; no need
        // to also animate the head.
    }

    // MARK: - Subtle idle motion

    private var reactionScale: CGFloat { 1.0 }
    private var reactionRotation: Double { 0 }

    // MARK: - Art (PNG asset → procedural fallback)

    @ViewBuilder
    private var avatarArt: some View {
        if let nsImage = bundledAvatarImage() {
            Image(nsImage: cropToHeadSquare(nsImage))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            CyberKGlyph()
                .frame(width: size, height: size)
        }
    }

    /// Crop a portrait avatar to a square focused on the head/shoulders.
    /// Assumes the head occupies roughly the top 40% of a portrait image.
    private func cropToHeadSquare(_ image: NSImage) -> NSImage {
        let imgSize = image.size
        // Choose a square crop sized to the image width (or 70% of height for safety),
        // anchored toward the top so the head is visible.
        let side = min(imgSize.width, imgSize.height * 0.7)
        // NSImage coordinate origin is bottom-left → "top" = imgSize.height - side
        let srcOriginY = max(0, imgSize.height - side - imgSize.height * 0.05) // tiny breathing room above the head
        let srcOriginX = (imgSize.width - side) / 2
        let srcRect = NSRect(x: srcOriginX, y: srcOriginY, width: side, height: side)

        let cropped = NSImage(size: NSSize(width: side, height: side))
        cropped.lockFocus()
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: srcRect,
            operation: .sourceOver,
            fraction: 1.0
        )
        cropped.unlockFocus()
        return cropped
    }

    private func bundledAvatarImage() -> NSImage? {
        // Prefer the selected character pack's portrait; fall back to the
        // legacy bundled girl assets.
        if let img = CharacterPackStore.currentPortraitImage() { return img }
        let candidates = ["doris-avatar", "doris-avatar-idle"]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Avatar") {
                if let img = NSImage(contentsOf: url) { return img }
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "png") {
                if let img = NSImage(contentsOf: url) { return img }
            }
        }
        return nil
    }
}

private struct ReactionFrame: Equatable {
    var scale: CGFloat = 1.0
    var rotation: Double = 0
    var bounce: CGFloat = 0
}

/// Procedural fallback: a stylised "K" glyph with neon cyan/pink gradient.
private struct CyberKGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.25, blue: 0.75),
                            Color(red: 0.0, green: 0.85, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            Text("K")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 1.0),
                            Color(red: 0.6, green: 1.0, blue: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(red: 1.0, green: 0.25, blue: 0.85).opacity(0.7), radius: 3)
        }
    }
}
