import Foundation
import SwiftUI
import DorisCore
#if os(macOS)
import AppKit
typealias RichFont = NSFont
typealias RichColor = NSColor
#else
import UIKit
typealias RichFont = UIFont
typealias RichColor = UIColor
#endif

extension NSAttributedString.Key {
    /// Which inline styles a run carries, kept beside the visible attributes
    /// (font, underline, background) so saving reads intent, not looks.
    static let dorisBold = NSAttributedString.Key("doris.bold")
    static let dorisUnderline = NSAttributedString.Key("doris.underline")
    static let dorisHighlight = NSAttributedString.Key("doris.highlight")
}

/// Bold, underline and highlight in the body editors: how each looks, and
/// how a selection or the typing style is switched. The text form lives in
/// `NoteInlineMarkup` (DorisCore).
@MainActor
enum NoteRichText {
    typealias Style = NoteInlineMarkup.Style
    typealias Highlight = NoteInlineMarkup.Highlight

    enum Command: Equatable {
        case bold
        case underline
        /// nil takes the highlight off.
        case highlight(Highlight?)
    }

    /// `base` (the editor's plain font, colour, paragraph) with `style` on top.
    static func attributes(_ style: Style, base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = base
        if style.bold {
            a[.dorisBold] = true
            if let font = base[.font] as? RichFont { a[.font] = bold(font) }
        }
        if style.underline {
            a[.dorisUnderline] = true
            a[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if let h = style.highlight {
            a[.dorisHighlight] = h.rawValue
            a[.backgroundColor] = color(h)
        }
        return a
    }

    /// A run's style: from our keys, or — where the text system dropped
    /// them (UIKit's typing attributes keep only what it draws) — from how
    /// the run looks: a bold font, an underline, one of our backgrounds.
    static func style(of attrs: [NSAttributedString.Key: Any]) -> Style {
        let bold = attrs[.dorisBold] as? Bool ?? (attrs[.font] as? RichFont).map(isBold) ?? false
        let underline = attrs[.dorisUnderline] as? Bool
            ?? ((attrs[.underlineStyle] as? Int).map { $0 != 0 } ?? false)
        let highlight = (attrs[.dorisHighlight] as? String).flatMap(Highlight.init(rawValue:))
            ?? (attrs[.backgroundColor] as? RichColor).flatMap(highlight(matching:))
        return Style(bold: bold, underline: underline, highlight: highlight)
    }

    static func isBold(_ font: RichFont) -> Bool {
        #if os(macOS)
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        #else
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    /// Which of our highlights a background colour is, by its hue.
    private static func highlight(matching color: RichColor) -> Highlight? {
        #if os(macOS)
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        return Highlight.allCases.first { h in
            let (hr, hg, hb) = rgb(h)
            return abs(hr - r) < 0.02 && abs(hg - g) < 0.02 && abs(hb - b) < 0.02
        }
    }

    private static func rgb(_ h: Highlight) -> (CGFloat, CGFloat, CGFloat) {
        switch h {
        case .red:    (1.00, 0.27, 0.23)
        case .green:  (0.20, 0.78, 0.35)
        case .yellow: (1.00, 0.80, 0.00)
        }
    }

    /// Soft enough to read black or white text on, in light and dark.
    static func color(_ h: Highlight) -> RichColor {
        let (r, g, b) = rgb(h)
        let light: CGFloat = h == .yellow ? 0.42 : 0.26
        let dark: CGFloat = h == .yellow ? 0.32 : 0.36
        #if os(macOS)
        return NSColor(name: nil) { ap in
            let isDark = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(srgbRed: r, green: g, blue: b, alpha: isDark ? dark : light)
        }
        #else
        return UIColor { t in
            UIColor(red: r, green: g, blue: b, alpha: t.userInterfaceStyle == .dark ? dark : light)
        }
        #endif
    }

    static func bold(_ font: RichFont) -> RichFont {
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #else
        guard let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitBold))
        else { return font }
        return UIFont(descriptor: d, size: font.pointSize)
        #endif
    }

    private static func applying(_ command: Command, to style: Style, turnOn: Bool) -> Style {
        var s = style
        switch command {
        case .bold: s.bold = turnOn
        case .underline: s.underline = turnOn
        case .highlight(let h): s.highlight = h
        }
        return s
    }

    /// Whether every character of `range` already has what `command` adds —
    /// then the command takes it off instead.
    static func isOn(_ command: Command, in text: NSAttributedString, range: NSRange) -> Bool {
        var all = true
        var sawText = false
        text.enumerateAttributes(in: range) { attrs, r, stop in
            if (text.string as NSString).substring(with: r) == NoteBodyTextBridge.attachmentChar { return }
            sawText = true
            let s = style(of: attrs)
            let on: Bool = switch command {
            case .bold: s.bold
            case .underline: s.underline
            case .highlight(let h): h != nil && s.highlight == h
            }
            if !on { all = false; stop.pointee = true }
        }
        return sawText && all
    }

    /// Apply `command` to `range` of `storage`: on, or off when the whole
    /// range already has it. Images and line breaks are left alone.
    static func apply(_ command: Command, to storage: NSMutableAttributedString, range: NSRange,
                      base: [NSAttributedString.Key: Any]) {
        let turnOn = !isOn(command, in: storage, range: range)
        let ns = storage.string as NSString
        var edits: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range) { attrs, r, _ in
            if attrs[.attachment] != nil { return }
            var s = applying(command, to: style(of: attrs), turnOn: turnOn)
            if case .highlight = command, !turnOn { s.highlight = nil }
            // Keep the run's own non-style attributes (paragraph, colour).
            var kept = attrs
            for k in [NSAttributedString.Key.dorisBold, .dorisUnderline, .dorisHighlight,
                      .underlineStyle, .backgroundColor] { kept[k] = nil }
            kept[.font] = base[.font] ?? attrs[.font]
            // Newlines carry no style, so a style never spans lines.
            if ns.substring(with: r) == "\n" { s = Style() }
            edits.append((r, attributes(s, base: kept)))
        }
        for (r, a) in edits { storage.setAttributes(a, range: r) }
    }

    /// The typing style after `command` with nothing selected.
    static func typingAttributes(_ current: [NSAttributedString.Key: Any], after command: Command,
                                 base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        attributes(typingStyle(style(of: current), after: command), base: base)
    }

    static func typingStyle(_ s: Style, after command: Command) -> Style {
        let on: Bool = switch command {
        case .bold: !s.bold
        case .underline: !s.underline
        case .highlight(let h): h != nil && s.highlight != h
        }
        var next = applying(command, to: s, turnOn: on)
        if case .highlight = command, !on { next.highlight = nil }
        return next
    }
}

// MARK: - Toolbar → editor

extension Notification.Name {
    /// `object` is a `NoteRichTextRequest`. The body editor showing that
    /// note applies it to its selection (or typing style).
    static let dorisRichTextCommand = Notification.Name("dorisRichTextCommand")
}

struct NoteRichTextRequest {
    let noteID: UUID
    let command: NoteRichText.Command
}

/// Bold · underline · highlight (yellow / green / red / off), for a note's
/// body editor. Works on the editor's selection, or on what's typed next.
struct NoteFormatBar: View {
    let noteID: UUID

    var body: some View {
        HStack(spacing: 2) {
            button("bold", L("Bold (⌘B)", "加粗 (⌘B)"), .bold)
            button("underline", L("Underline (⌘U)", "下划线 (⌘U)"), .underline)
            Menu {
                ForEach(NoteInlineMarkup.Highlight.allCases, id: \.self) { h in
                    Button {
                        send(.highlight(h))
                    } label: {
                        Label(Self.name(h), systemImage: "circle.fill")
                    }
                }
                Divider()
                Button(L("Remove Highlight", "清除高亮")) { send(.highlight(nil)) }
            } label: {
                Image(systemName: "highlighter")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 22)
            } primaryAction: {
                send(.highlight(.yellow))
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            #endif
            .help(L("Highlight — click for yellow (⌘⇧H), or pick a colour",
                    "高亮 — 点按为黄色 (⌘⇧H),也可选颜色"))
        }
        .foregroundStyle(.primary.opacity(0.7))
    }

    static func name(_ h: NoteInlineMarkup.Highlight) -> String {
        switch h {
        case .yellow: L("Yellow", "黄色")
        case .green:  L("Green", "绿色")
        case .red:    L("Red", "红色")
        }
    }

    private func button(_ symbol: String, _ help: String, _ command: NoteRichText.Command) -> some View {
        Button { send(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func send(_ command: NoteRichText.Command) {
        NotificationCenter.default.post(name: .dorisRichTextCommand,
                                        object: NoteRichTextRequest(noteID: noteID, command: command))
    }
}
