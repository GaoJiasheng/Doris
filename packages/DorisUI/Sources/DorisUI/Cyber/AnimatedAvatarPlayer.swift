import SwiftUI
#if os(macOS)
import AppKit
public typealias HeroPlatformImage = NSImage
#else
import UIKit
public typealias HeroPlatformImage = UIImage
#endif

/// Plays one of the bundled cyber-girl mood clips as a sequence of PNG
/// frames. Loop moods cycle indefinitely; one-shot moods play once and
/// then signal completion via `onFinished` (the parent view typically
/// uses that to drop back to the loop mood).
///
/// Frames live at `DorisCharacters.bundle/HeroAnim/<mood>/<mood>_NNNN.png` and are
/// loaded lazily on first use, then cached per-mood. A weak shared cache
/// across all instances keeps memory in check when two screens (Mac
/// dropdown panel + main window) play the same mood.
public struct AnimatedAvatarPlayer: View {
    /// Underlying clip name on disk (e.g. "idle", "greeting"). Drives both
    /// the directory lookup and the `<mood>_NNNN.png` filename prefix.
    let clip: String
    /// True for ambient loops (idle, listening, walking, sleeping). False
    /// for one-shot reactions (greeting, alerted, celebrating, confused).
    let isLooping: Bool
    /// Source frame rate. The bundled clips were rendered at 16 fps so
    /// playback at 16 fps maps frames 1:1 to the AI-generated motion.
    let fps: Double
    /// Pushes the rendered image down by this many points within the
    /// player's frame; the corresponding overflow at the bottom is clipped.
    /// Use this to leave headroom for an overlay (e.g. the weather pill)
    /// without shrinking the character itself.
    let verticalOffset: CGFloat
    /// Fired once after a one-shot clip finishes its single play-through.
    /// Looping clips never fire this. Use it to revert mood → idle.
    let onFinished: (() -> Void)?
    /// Subdirectory in `DorisCharacters.bundle` holding the per-mood frame folders
    /// for the active character pack — e.g. "HeroAnim" (built-in girl) or
    /// "Characters/<id>/anim". Frames load from `<animDirectory>/<clip>/`.
    let animDirectory: String
    /// When true, freeze on a single static frame with NO `TimelineView`, so
    /// the periodic frame timer stops firing entirely. Driven by the host's
    /// window visibility (see AvatarHero) — a hidden / occluded window then
    /// burns zero CPU on avatar animation.
    let paused: Bool

    public init(
        clip: String,
        isLooping: Bool,
        fps: Double = 16,
        verticalOffset: CGFloat = 0,
        animDirectory: String = "HeroAnim",
        paused: Bool = false,
        onFinished: (() -> Void)? = nil
    ) {
        self.clip = clip
        self.isLooping = isLooping
        self.fps = fps
        self.verticalOffset = verticalOffset
        self.animDirectory = animDirectory
        self.paused = paused
        self.onFinished = onFinished
    }

    @State private var frames: [HeroPlatformImage] = []
    @State private var startTime: Date = Date()
    @State private var lastClip: String = ""
    @State private var hasFired: Bool = false

    public var body: some View {
        // Keep the offset / clipped / onAppear modifiers OUTSIDE the
        // TimelineView. If they live inside the timeline closure, SwiftUI
        // re-applies them on every tick, which the layout engine has to
        // chew through. Outside the closure they attach once and only
        // the Image swap inside happens at the configured fps.
        //
        // `.periodic` schedule (vs `.animation`) uses a plain dispatch
        // timer instead of binding to the display link. Frame-accurate
        // sync isn't useful for a 10fps PNG sequence anyway, and it
        // stops SwiftUI's `AnimatorState` from ticking at the display's
        // refresh rate — which was the dominant CPU cost.
        Group {
            if paused {
                // Off-screen / occluded host: hold a single static frame with
                // NO TimelineView, so the periodic timer stops firing. This is
                // the main energy win — a hidden window animates nothing.
                content(at: startTime)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / max(fps, 1.0))) { context in
                    content(at: context.date)
                }
            }
        }
        .offset(y: verticalOffset)
        .clipped()
        .onAppear { ensureLoaded() }
        .onChange(of: clip) { _, _ in
            ensureLoaded()
            startTime = Date()
            hasFired = false
        }
        // Pack switch: same mood name ("idle"), different frames — reload.
        .onChange(of: animDirectory) { _, _ in
            ensureLoaded()
            startTime = Date()
            hasFired = false
        }
        // Resume cleanly: restart the clip from frame 0 when we come back on
        // screen, so a looping mood doesn't jump to a far-future frame based
        // on wall-clock elapsed while it was paused.
        .onChange(of: paused) { _, isPaused in
            if !isPaused {
                startTime = Date()
                hasFired = false
            }
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        if frames.isEmpty {
            // Fallback while loading or if assets are missing — show
            // nothing rather than a flash of placeholder.
            Color.clear
        } else {
            frameImage(at: frameIndex(now: now))
        }
    }

    private func frameIndex(now: Date) -> Int {
        let elapsed = now.timeIntervalSince(startTime)
        let frameDuration = 1.0 / fps
        let total = frames.count
        let rawIndex = Int(elapsed / frameDuration)
        if isLooping {
            return rawIndex % total
        } else if rawIndex >= total {
            // One-shot finished — hold the last frame, fire callback once.
            if !hasFired {
                DispatchQueue.main.async {
                    hasFired = true
                    onFinished?()
                }
            }
            return total - 1
        } else {
            return rawIndex
        }
    }

    @ViewBuilder
    private func frameImage(at index: Int) -> some View {
        // `.aspectRatio(contentMode: .fill)` over-fills the parent in one
        // dimension; the wrapping `.clipped()` in `body` crops the
        // overflow. This way the clip's character (1:1.5 aspect) fills the
        // taller card (1:1.9 aspect) without leaving an empty band at top
        // and bottom.
        #if os(macOS)
        Image(nsImage: frames[index])
            .interpolation(.medium)
            .antialiased(true)
            .resizable()
            .aspectRatio(contentMode: .fill)
        #else
        Image(uiImage: frames[index])
            .interpolation(.medium)
            .antialiased(true)
            .resizable()
            .aspectRatio(contentMode: .fill)
        #endif
    }

    private func ensureLoaded() {
        // Key by pack dir + clip so switching packs reloads even when the
        // mood name is unchanged (e.g. both packs' "idle").
        let key = "\(animDirectory)/\(clip)"
        if key == lastClip, !frames.isEmpty { return }
        lastClip = key
        frames = HeroFrameCache.shared.frames(animDirectory: animDirectory, clip: clip)
    }
}

/// In-process cache keyed by mood clip name. The DorisCharacters.bundle lookup is
/// cheap but decoding 65 PNGs adds up — cache the decoded array so a
/// second screen showing the same clip doesn't re-decode.
final class HeroFrameCache: @unchecked Sendable {
    static let shared = HeroFrameCache()

    private let lock = NSLock()
    private var cache: [String: [HeroPlatformImage]] = [:]

    func frames(animDirectory: String, clip: String) -> [HeroPlatformImage] {
        let key = "\(animDirectory)/\(clip)"
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        // Look for files at <animDirectory>/<clip>/<clip>_*.png in the
        // character-art bundle. Absent on iOS, which ships no artwork.
        guard let bundle = CharacterArtBundle.bundle else { return [] }
        guard let urls = bundle.urls(
            forResourcesWithExtension: "png",
            subdirectory: "\(animDirectory)/\(clip)"
        ) else {
            return []
        }
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var loaded: [HeroPlatformImage] = []
        loaded.reserveCapacity(sorted.count)
        for u in sorted {
            #if os(macOS)
            if let img = NSImage(contentsOf: u) { loaded.append(img) }
            #else
            if let data = try? Data(contentsOf: u),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
            #endif
        }

        lock.lock()
        cache[key] = loaded
        lock.unlock()
        return loaded
    }
}
