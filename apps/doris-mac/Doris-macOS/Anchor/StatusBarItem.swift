import AppKit
import SwiftUI
import DorisIPC
import DorisUI

/// Owns the NSStatusItem that lives in the macOS menu bar. Status items are the only
/// supported way to put content INSIDE the menu bar area — regular NSPanels get clamped
/// out of it by the window server regardless of level / collection behavior.
@MainActor
final class StatusBarItem {
    private let item: NSStatusItem
    private let onClick: (NSStatusBarButton) -> Void

    init(onClick: @escaping (NSStatusBarButton) -> Void) {
        self.onClick = onClick
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configure()
    }

    /// Position (in screen coordinates) where a sibling panel should anchor below.
    /// Returns the frame of the status button on screen, or nil if not yet placed.
    var screenFrame: NSRect? {
        guard let win = item.button?.window else { return nil }
        return win.frame
    }

    /// The screen the status item is rendered on (the menu-bar screen).
    var screen: NSScreen? {
        item.button?.window?.screen
    }

    private func configure() {
        guard let button = item.button else { return }
        button.image = makeAvatarImage()
        button.image?.isTemplate = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let button = item.button else { return }
        onClick(button)
    }

    /// Build a 22pt circular cropped image from the bundled avatar, with a transparent
    /// fallback if the asset isn't found.
    private func makeAvatarImage() -> NSImage {
        let size: CGFloat = 22
        let raw: NSImage = bundledAvatar() ?? fallbackGlyph(size: size)
        // Crop the source to a head-focused square, then mask into a circle.
        let cropped = cropToHeadSquare(raw)
        return circleMask(cropped, diameter: size)
    }

    private func bundledAvatar() -> NSImage? {
        // Prefer the selected character pack's portrait; fall back to the
        // legacy bundled girl assets.
        if let img = CharacterPackStore.currentPortraitImage() { return img }
        let candidates = ["doris-avatar", "doris-avatar-idle"]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Avatar"),
               let img = NSImage(contentsOf: url) {
                return img
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return nil
    }

    private func fallbackGlyph(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .heavy),
            .foregroundColor: NSColor.cyan
        ]
        let s = "K" as NSString
        let textSize = s.size(withAttributes: attr)
        s.draw(
            at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2),
            withAttributes: attr
        )
        img.unlockFocus()
        return img
    }

    private func cropToHeadSquare(_ image: NSImage) -> NSImage {
        let imgSize = image.size
        let side = min(imgSize.width, imgSize.height * 0.7)
        let srcOriginY = max(0, imgSize.height - side - imgSize.height * 0.05)
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

    private func circleMask(_ image: NSImage, diameter: CGFloat) -> NSImage {
        let result = NSImage(size: NSSize(width: diameter, height: diameter))
        result.lockFocus()
        let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        path.addClip()
        image.draw(
            in: NSRect(x: 0, y: 0, width: diameter, height: diameter),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        result.unlockFocus()
        return result
    }
}
