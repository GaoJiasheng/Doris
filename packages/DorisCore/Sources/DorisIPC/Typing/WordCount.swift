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
