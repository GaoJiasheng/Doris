import AppKit
import ApplicationServices
import DorisIPC

/// Counts the words you produce — typed, picked from an input method,
/// dictated, pasted by a voice tool, or typed over a remote-control
/// session — by watching the focused text field through Accessibility.
/// Only word counts leave this class; the text is read, counted and
/// dropped (the last value of the current field is held in memory, to
/// tell an insertion from a replacement).
///
/// How a count is made: when the field settles, count the words in its
/// whole text and compare with the last count. Counting whole text
/// rather than keystrokes is what makes input methods come out right:
/// pinyin still being composed ("nihao") is one word, committing it
/// ("你好") turns that into two — the final text, not the keys.
///
/// A field settles 0.8 s after its last change, on a 1 s poll while
/// you're typing (some apps never announce an input method's commit),
/// and on Return *before* the app sees it — so a message is counted
/// before sending empties the field.
///
/// - A rise counts if you typed since the last settle — a key that
///   produces or edits text (real or remote), not a shortcut or an arrow
///   — and only up to a few words per key (`TypingRules.allowance`): new
///   text after ⌘K or Page Down is a chat's draft or a document loading,
///   not typing. Input posted by software counts in full: a ⌘V (voice
///   tools like Typeless paste that way) or keys carrying text (others
///   type it); a rise after your own ⌘V is a paste and doesn't count. With no key at all, a rise counts only if it's a pure
///   insertion that leaves the caret right after it — dictation and voice
///   input methods type without keys, while a chat switching drafts
///   replaces the text and a document scrolling into view adds it away
///   from the caret.
/// - A fall gives back at most what this field credited in the last
///   minute (fixing a typo), and nothing when the field is emptied: a
///   message sent.
/// - What a field shows right after you send (an empty box, or a
///   placeholder like Feishu's "发送给 …", which it exposes as text) is
///   remembered and counted as zero words from then on.
/// - Text that comes back whole after leaving a field (the ↑ key recalling
///   the last message, undo, a restored draft, a stale paste) was already
///   counted, so it isn't counted again. Remembered as a hash, for ten
///   minutes, and only for three words or more — a short "好的" sent twice
///   is two messages.
/// - Terminals are skipped: their text includes program output.
@MainActor
final class TypingCounter {
    static let shared = TypingCounter()

    /// Words credited (or given back, negative), when, and in which app.
    var onWords: ((Int, Date, String) -> Void)?

    private var running = false
    private var observer: AXObserver?
    private var observedPid: pid_t = 0
    private var observedBundle = ""
    private var skipped = false
    private var tap: CFMachPort?
    private var activationObserver: NSObjectProtocol?
    private var timers: [Timer] = []

    // The field being watched.
    private var element: AXUIElement?
    private var focusedAt = Date.distantPast
    private var lastText: String?
    private var lastWords: Int?
    private var settleWork: DispatchWorkItem?
    private var lastSettleAt = Date.distantPast
    /// Text that recently left a field, per app, as hashes.
    private var gone: [pid_t: [(hash: Int, at: Date)]] = [:]
    /// Words credited to the current field recently (for typo give-backs).
    private var credits: [(at: Date, words: Int)] = []

    // Input since the last settle.
    /// Keys that produce or edit text.
    private var keysSinceSettle = 0
    /// A ⌘V or text keys posted by software — a voice tool pasting or
    /// typing what you said, or a remote-control session.
    private var softPasteSinceSettle = false
    /// Your own ⌘V: a paste, not typing.
    private var pasteSinceSettle = false
    private var inputSinceSettle: Bool { keysSinceSettle > 0 || softPasteSinceSettle }
    /// The most this settle may credit for typed input.
    private var allowance: Int {
        softPasteSinceSettle ? .max : TypingRules.allowance(keys: keysSinceSettle)
    }
    private var lastKeyAt = Date.distantPast
    private var sentAt = Date.distantPast
    /// Hashes of what fields show when empty, per app. In memory only.
    private var emptyStates: [pid_t: Set<Int>] = [:]

    private init() {}

    /// `DORIS_TYPING_DEBUG=1`: log each settle's numbers (never text).
    private let debug = ProcessInfo.processInfo.environment["DORIS_TYPING_DEBUG"] == "1"
    private func trace(_ s: @autoclosure () -> String) {
        guard debug, let dir = try? TypingWire.directory() else { return }
        let line = "\(Date().timeIntervalSince1970) \(s())\n"
        let url = dir.appendingPathComponent("debug.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    func start() {
        guard !running else { return }
        running = true
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app { TypingCounter.shared.observe(app) } }
        }
        // Access can be granted while the helper runs; pick it up without a relaunch.
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { TypingCounter.shared.attachIfTrusted() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { TypingCounter.shared.poll() }
        })
        attachIfTrusted()
    }

    private func attachIfTrusted() {
        guard isTrusted else { return }
        if tap == nil { installTap() }
        if observer == nil, let front = NSWorkspace.shared.frontmostApplication { observe(front) }
    }

    // MARK: Keys

    /// A listen-only tap rather than an NSEvent monitor: it runs before the
    /// app handles the key, which is what lets Return count a message
    /// before it's sent.
    private func installTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .keyDown {
                    MainActor.assumeIsolated { TypingCounter.shared.key(event) }
                } else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { TypingCounter.shared.reenableTap() }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: nil) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
    }

    private func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func key(_ e: CGEvent) {
        let code = e.getIntegerValueField(.keyboardEventKeycode)
        if code == 36 || code == 76 {   // Return, keypad Enter
            trace("return")
            settle()                    // the text as it is before the app acts on it
            sentAt = Date()
            return
        }
        lastKeyAt = Date()
        let command = e.flags.contains(.maskCommand), control = e.flags.contains(.maskControl)
        if command && code == 9 {   // ⌘V
            if Self.isOwnKeyboard(e) { pasteSinceSettle = true } else { softPasteSinceSettle = true }
        } else if TypingRules.isTypingKey(code: code, command: command, control: control) {
            keysSinceSettle += 1
            // A tool can put a whole phrase in one posted key.
            if !Self.isOwnKeyboard(e) { softPasteSinceSettle = true }
        }
    }

    /// A key from this Mac's own keyboard, as opposed to one posted by an
    /// app (voice tools) or a remote-control tool's background server.
    private static func isOwnKeyboard(_ e: CGEvent) -> Bool {
        // 1 = kCGEventSourceStateHIDSystemState.
        guard e.getIntegerValueField(.eventSourceStateID) == 1 else { return false }
        let pid = pid_t(e.getIntegerValueField(.eventSourceUnixProcessID))
        // Hardware events carry no posting app; an app posting with the
        // HID state still shows up as itself.
        return pid == 0 || NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == nil
    }

    // MARK: Observing the focused field

    private func observe(_ app: NSRunningApplication) {
        guard isTrusted else { return }
        settle()   // finish the field we're leaving
        if let o = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
            observer = nil
        }
        reset(to: nil)
        observedPid = app.processIdentifier
        observedBundle = app.bundleIdentifier ?? ""
        skipped = TypingWire.skippedBundles.contains(app.bundleIdentifier ?? "")
            || app.bundleIdentifier == Bundle.main.bundleIdentifier
        guard !skipped else { return }

        let appEl = AXUIElementCreateApplication(observedPid)
        // Electron / Chromium only build their accessibility tree when asked.
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var o: AXObserver?
        let cb: AXObserverCallback = { _, el, notif, _ in
            let name = notif as String
            MainActor.assumeIsolated { TypingCounter.shared.axEvent(el, name) }
        }
        guard AXObserverCreate(observedPid, cb, &o) == .success, let o else { return }
        AXObserverAddNotification(o, appEl, kAXValueChangedNotification as CFString, nil)
        AXObserverAddNotification(o, appEl, kAXFocusedUIElementChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observer = o
        if let focused = Self.focusedElement(of: observedPid) { focus(focused) }
    }

    private func axEvent(_ el: AXUIElement, _ notif: String) {
        if notif == kAXFocusedUIElementChangedNotification {
            focus(el)
            return
        }
        // Some apps never announce focus, so a change elsewhere may mean we
        // moved — but only trust that when the app's focused element says
        // so: Feishu's web area announces every keystroke alongside the box.
        if element == nil || !CFEqual(element!, el),
           let focused = Self.focusedElement(of: observedPid),
           element == nil || !CFEqual(element!, focused) {
            focus(focused)
        }
        scheduleSettle()
    }

    /// While you're typing, look at the focused field every second: input
    /// method commits and focus moves aren't always announced.
    private func poll() {
        guard observer != nil, !skipped, Date().timeIntervalSince(lastKeyAt) < 15 else { return }
        if let focused = Self.focusedElement(of: observedPid) {
            if element == nil || !CFEqual(element!, focused) { focus(focused); return }
        }
        // Even mid-burst: waiting for a pause could mean waiting until Return.
        if Date().timeIntervalSince(lastSettleAt) >= 1 { settle() }
    }

    private func focus(_ el: AXUIElement) {
        if let current = element, CFEqual(current, el) { return }
        settle()
        reset(to: el)
    }

    private func reset(to el: AXUIElement?) {
        trace("focus \(el.flatMap { Self.attr($0, kAXRoleAttribute) as? String } ?? "none") app=\(observedBundle)")
        element = el
        focusedAt = Date()
        credits.removeAll()
        lastText = el.flatMap(Self.text(of:))
        lastWords = lastText.map(words(in:))
    }

    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { TypingCounter.shared.settle() } }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: Counting

    /// Remembers text that just left a field, to spot it coming back.
    private func rememberGone(_ text: String?, words: Int) {
        guard let text, words >= 3 else { return }
        let now = Date()
        gone[observedPid, default: []].removeAll { now.timeIntervalSince($0.at) > 600 }
        gone[observedPid, default: []].append((Self.goneKey(text), now))
    }

    private func isBack(_ text: String, words: Int) -> Bool {
        guard words >= 3 else { return false }
        let now = Date(), key = Self.goneKey(text)
        return gone[observedPid]?.contains { $0.hash == key && now.timeIntervalSince($0.at) <= 600 } == true
    }

    private static func goneKey(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hashValue
    }

    private func words(in text: String) -> Int {
        emptyStates[observedPid]?.contains(text.hashValue) == true ? 0 : WordCount.count(text)
    }

    private func settle() {
        settleWork?.cancel()
        settleWork = nil
        lastSettleAt = Date()
        guard let el = element, let text = Self.text(of: el) else { return }
        let now = Date()
        // The first state after a send is what this app's fields look like empty.
        if now.timeIntervalSince(sentAt) < 2, text != lastText {
            emptyStates[observedPid, default: []].insert(text.hashValue)
            sentAt = .distantPast
        }
        let count = words(in: text)
        let previousText = lastText
        trace("settle last=\(lastWords.map(String.init) ?? "nil") now=\(count) raw=\(WordCount.count(text)) len=\(text.utf16.count) keys=\(keysSinceSettle) softPaste=\(softPasteSinceSettle) paste=\(pasteSinceSettle) sentAgo=\(Int(now.timeIntervalSince(sentAt) * 1000)) empties=\(emptyStates[observedPid]?.count ?? 0)")
        defer {
            keysSinceSettle = 0
            softPasteSinceSettle = false
            pasteSinceSettle = false
            lastText = text
            lastWords = count
        }
        guard let last = lastWords else { return }
        let delta = count - last
        credits.removeAll { now.timeIntervalSince($0.at) > 60 }

        // A chunk of words swapped for new text — a placeholder giving way
        // to what you type, or a selection typed over: count what was typed,
        // not the difference in totals.
        // (An input method committing pinyin — "ni hao" → "你好" — is a
        // swap too, but the pinyin was already counted: the totals handle it.)
        if count > 0, last > 0, let c = Self.change(from: previousText, to: text),
           c.removed >= 3, c.inserted > 0, !c.isCommit {
            guard inputSinceSettle, !pasteSinceSettle else { return }
            credit(min(c.inserted, allowance), at: now)
            return
        }

        if delta > 0 {
            guard !isBack(text, words: count) else { return }
            guard !pasteSinceSettle else { return }
            if inputSinceSettle {
                credit(min(delta, allowance), at: now)
            } else if now.timeIntervalSince(focusedAt) > 1,
                      let c = Self.change(from: previousText, to: text), c.removedText == 0,
                      Self.caretIsAfter(c, in: el) != false {
                credit(min(delta, TypingRules.keylessMax), at: now)
            }
        } else if delta < 0 {
            // Emptied (a message sent) or most of it gone at once: not typing.
            if count <= 1 { rememberGone(previousText, words: last) }
            guard count > 1, count * 2 >= last, inputSinceSettle else { return }
            var owed = min(-delta, credits.reduce(0) { $0 + $1.words })
            let back = owed
            while owed > 0, let c = credits.popLast() {
                let take = min(owed, c.words)
                owed -= take
                if c.words > take { credits.append((c.at, c.words - take)) }
            }
            if back > 0 { onWords?(-back, now, observedBundle) }
        }
    }

    private func credit(_ n: Int, at date: Date) {
        guard n > 0 else { return }
        credits.append((date, n))
        onWords?(n, date, observedBundle)
    }

    /// What changed between two values of a field: the words in the span
    /// that was removed and in the span put in its place (`removedText` is
    /// that span's length, so 0 means a pure insertion).
    private static func change(from old: String?, to new: String)
        -> (removed: Int, inserted: Int, removedText: Int, isCommit: Bool, at: Int, insertedText: Int)? {
        guard let old else { return nil }
        let o = Array(old.utf16), n = Array(new.utf16)
        var p = 0
        while p < o.count, p < n.count, o[p] == n[p] { p += 1 }
        var s = 0
        while s < o.count - p, s < n.count - p, o[o.count - 1 - s] == n[n.count - 1 - s] { s += 1 }
        let removed = String(decoding: o[p..<(o.count - s)], as: UTF16.self)
        let inserted = String(decoding: n[p..<(n.count - s)], as: UTF16.self)
        // Latin letters (with the separators input methods show) giving way
        // to CJK: an input method committing its composition.
        let latin = !removed.isEmpty && removed.unicodeScalars.allSatisfy {
            ($0.isASCII && (CharacterSet.letters.contains($0) || $0 == " " || $0 == "'")) || $0 == "\u{2006}"
        }
        let commit = latin && inserted.unicodeScalars.contains { WordCount.isCJK($0.value) }
        return (WordCount.count(removed), WordCount.count(inserted), o.count - s - p, commit,
                p, n.count - s - p)
    }

    /// Whether the caret sits right after an insertion, as it does after
    /// dictation or a voice input method; nil when the field won't say.
    private static func caretIsAfter(_ c: (removed: Int, inserted: Int, removedText: Int, isCommit: Bool,
                                           at: Int, insertedText: Int),
                                     in el: AXUIElement) -> Bool? {
        guard let v = attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else {
            return nil
        }
        var r = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &r) else { return nil }
        return r.length == 0 && r.location == c.at + c.insertedText
    }

    // MARK: AX helpers

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func focusedElement(of pid: pid_t) -> AXUIElement? {
        guard pid != 0, let f = attr(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)
        else { return nil }
        return (f as! AXUIElement)
    }

    /// A text element's whole value, or nil if it has none (not a text
    /// field, a password field, unreadable, or too big to recount).
    private static func text(of el: AXUIElement) -> String? {
        if attr(el, kAXRoleAttribute) as? String == "AXSecureTextField"
            || attr(el, kAXSubroleAttribute) as? String == "AXSecureTextField" { return nil }
        guard let text = attr(el, kAXValueAttribute) as? String else { return nil }
        guard text.utf16.count <= 400_000 else { return nil }
        return text
    }
}
