import Foundation

// MARK: - Word counting

public enum WordCount {
    /// Word-processor style count: every CJK character (Han, kana, Hangul)
    /// is one, every run of other letters or digits is one; punctuation,
    /// spaces and emoji count nothing.
    public static func count(_ s: String) -> Int {
        var n = 0
        var inWord = false
        for u in s.unicodeScalars {
            if isCJK(u.value) {
                n += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(u) {
                if !inWord { n += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return n
    }

    public static func isCJK(_ v: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
            || (0x20000...0x2EBEF).contains(v) || (0xF900...0xFAFF).contains(v)
            || (0x3040...0x30FF).contains(v) || (0xAC00...0xD7AF).contains(v)
    }
}

// MARK: - What counts as typing

/// The typing helper's limits on what a change in a field may credit —
/// pure, so they can be tested without Accessibility.
public enum TypingRules {
    /// Keys that move around or run commands rather than produce text:
    /// arrows, Home/End, Page Up/Down, Escape, Tab, Help and F1–F20.
    /// Delete and Forward Delete are edits, so they still count.
    static let nonTypingKeys: Set<Int64> = [
        123, 124, 125, 126, 115, 119, 116, 121, 53, 48, 114,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// True for a key that produces or edits text. Shortcuts (⌘ or ⌃
    /// held) and navigation keys don't: after them, new text in the field
    /// is a chat's draft, a document scrolling into view or another file,
    /// not something typed. (⌘V is handled on its own.)
    public static func isTypingKey(code: Int64, command: Bool, control: Bool) -> Bool {
        !command && !control && !nonTypingKeys.contains(code)
    }

    /// The most words one settle may credit after `keys` typing keys: an
    /// input method's suggestion turns one key into a phrase, a text
    /// replacement a few keys into a sentence — but not into a page.
    public static func allowance(keys: Int) -> Int {
        keys * 4 + 2
    }

    /// The most words one keyless insertion (dictation, a voice input
    /// method) may credit.
    public static let keylessMax = 300
}
