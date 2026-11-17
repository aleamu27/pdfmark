import AppKit

/// Owns the menu bar icon and its transient state changes: idle bookmark glyph,
/// a brief checkmark flash on success, and a brief exclamation flash on error.
final class StatusIconController {
    let statusItem: NSStatusItem
    private var revertTimer: Timer?
    private let flashDuration: TimeInterval = 1.2

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.image(systemName: "bookmark", accessibilityDescription: "PDFMark")
        }
    }

    func flashSuccess() {
        flash(systemName: "checkmark.circle.fill")
    }

    func flashError() {
        flash(systemName: "exclamationmark.circle.fill")
    }

    private func flash(systemName: String) {
        revertTimer?.invalidate()
        setImage(systemName)
        revertTimer = Timer.scheduledTimer(withTimeInterval: flashDuration, repeats: false) { [weak self] _ in
            self?.setImage("bookmark")
        }
    }

    /// Cross-fades between icons instead of snapping.
    private func setImage(_ systemName: String) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.2
        button.layer?.add(fade, forKey: "iconFade")
        button.image = Self.image(systemName: systemName, accessibilityDescription: "PDFMark")
    }

    private static func image(systemName: String, accessibilityDescription: String) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = (systemName == "bookmark")
        return image
    }
}
