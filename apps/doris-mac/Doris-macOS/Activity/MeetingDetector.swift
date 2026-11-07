import AppKit
import CoreAudio
import DorisCore

/// Marks the minutes this Mac spends in a Feishu (Lark) meeting.
///
/// Feishu runs meetings in a process of their own ("飞书会议",
/// `com.bytedance.macos.feishu.iron`) that starts when you join and quits
/// a few seconds after you leave. While you're in, it keeps both the
/// microphone and the speakers open — muting yourself doesn't release the
/// mic — so "the meeting process is using audio" holds for the whole
/// meeting, muted or not. Requiring audio leaves out the few seconds of
/// the pre-join screen, and voice messages or videos in chats, which play
/// from the main Feishu process.
///
/// Read through CoreAudio's process objects (macOS 14.2+): no permission
/// prompt, works in the sandbox.
@MainActor
final class MeetingDetector {
    static let shared = MeetingDetector()

    private var timer: Timer?
    private init() {}

    func start() {
        guard timer == nil else { return }
        // Well under the 30 s slot, so every slot of a meeting gets marked.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { MeetingDetector.shared.sample() }
        }
        timer?.tolerance = 2
        sample()
    }

    private func sample() {
        guard Self.inMeeting() else { return }
        ActivityRecorder.shared?.markMeeting()
    }

    static let meetingBundles: Set<String> = ["com.bytedance.macos.feishu.iron"]

    /// True while a Feishu meeting process has audio running.
    static func inMeeting() -> Bool {
        // Cheap check first: no meeting process, no meeting.
        guard NSWorkspace.shared.runningApplications.contains(where: {
            meetingBundles.contains($0.bundleIdentifier ?? "")
        }) else { return false }
        for o in audioProcessObjects() {
            guard let b = string(o, kAudioProcessPropertyBundleID), meetingBundles.contains(b) else { continue }
            if uint32(o, kAudioProcessPropertyIsRunningInput) != 0
                || uint32(o, kAudioProcessPropertyIsRunningOutput) != 0 { return true }
        }
        return false
    }

    // MARK: CoreAudio process objects

    private static func address(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioProcessObjects() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func uint32(_ o: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = address(sel)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(o, &a, 0, nil, &size, &v) == noErr ? v : 0
    }

    private static func string(_ o: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = address(sel)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(o, &a, 0, nil, &size, &s) == noErr, let s else { return nil }
        return s.takeRetainedValue() as String
    }
}
