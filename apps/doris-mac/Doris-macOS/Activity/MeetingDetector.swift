import Foundation
import CoreAudio
import DorisCore

/// Marks the minutes this Mac spends in a video meeting: Feishu / Lark
/// (every edition), Zoom, Tencent Meeting (腾讯会议) or DingTalk (钉钉).
///
/// The signal is "the meeting app is using audio", read per process
/// through CoreAudio's process objects (macOS 14.2+: no permission prompt,
/// works in the sandbox). Each app needs its own rule, because not all of
/// them run meetings in a process of their own:
///
/// - **Feishu / Lark** run a meeting in a separate process ("飞书会议",
///   bundle ID `<app>.iron`: `com.bytedance.macos.feishu.iron`, or
///   `com.larksuite.larkApp.iron` for international Lark) that starts when
///   you join and quits a few seconds after you leave. It keeps the mic and
///   the speakers open the whole time, muted or not, so mic *or* speakers
///   counts. Voice messages and videos in chats play from the main process
///   and don't.
/// - **Zoom** and **Tencent Meeting** are meeting apps and open audio only
///   in a meeting, so mic or speakers counts.
/// - **DingTalk** also plays message sounds, voice messages and videos, so
///   it counts only while it holds the microphone.
///
/// Bundle IDs match by prefix, so a helper process that carries the audio
/// counts as its app.
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

    struct Rule {
        /// Matches when the audio process's bundle ID is accepted by this.
        let matches: (String) -> Bool
        /// Microphone only (speakers alone could be a message sound).
        let needsMic: Bool
    }

    static let rules: [Rule] = [
        // Feishu / Lark: only the dedicated meeting process.
        Rule(matches: { b in
            b.hasSuffix(".iron")
                && (b.hasPrefix("com.bytedance.macos.feishu") || b.hasPrefix("com.larksuite.")
                    || b.hasPrefix("com.bytedance.macos.lark") || b.hasPrefix("com.electron.lark"))
        }, needsMic: false),
        Rule(matches: { $0.hasPrefix("us.zoom.xos") }, needsMic: false),
        Rule(matches: { $0.hasPrefix("com.tencent.meeting") || $0.hasPrefix("com.tencent.tencentmeeting") },
             needsMic: false),
        Rule(matches: { $0.hasPrefix("com.alibaba.DingTalk") || $0.hasPrefix("com.alibaba.dingtalk") },
             needsMic: true),
    ]

    /// True while one of the meeting apps is using audio per its rule.
    static func inMeeting() -> Bool {
        for o in audioProcessObjects() {
            guard let b = string(o, kAudioProcessPropertyBundleID), !b.isEmpty,
                  let rule = rules.first(where: { $0.matches(b) }) else { continue }
            let mic = uint32(o, kAudioProcessPropertyIsRunningInput) != 0
            let speakers = uint32(o, kAudioProcessPropertyIsRunningOutput) != 0
            if mic || (!rule.needsMic && speakers) { return true }
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
