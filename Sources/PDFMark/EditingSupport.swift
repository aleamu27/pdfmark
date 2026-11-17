import AppKit

/// PDFMark is a menu-bar-only app with no Edit menu, which is what normally
/// turns ⌘V/⌘C/⌘X/⌘A/⌘Z into editing actions. Without this, paste etc.
/// silently do nothing in text fields. Windows and panels route their key
/// equivalents through here first.
enum EditingShortcuts {
    static func handle(_ event: NSEvent, from sender: Any?) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift] else { return false }
        let action: Selector?
        switch (event.charactersIgnoringModifiers?.lowercased(), flags.contains(.shift)) {
        case ("v", false): action = #selector(NSText.paste(_:))
        case ("c", false): action = #selector(NSText.copy(_:))
        case ("x", false): action = #selector(NSText.cut(_:))
        case ("a", false): action = #selector(NSText.selectAll(_:))
        case ("z", false): action = Selector(("undo:"))
        case ("z", true): action = Selector(("redo:"))
        default: action = nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: sender)
    }
}

/// A regular window with working editing shortcuts (see `EditingShortcuts`).
final class EditingWindow: NSWindow {
    /// Called for ⌫/⌦ that nothing else handled (i.e. not while typing in a
    /// text field, which consumes the key itself).
    var onDeleteKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty, event.keyCode == 51 || event.keyCode == 117, let onDeleteKey {
            onDeleteKey()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        EditingShortcuts.handle(event, from: self) || super.performKeyEquivalent(with: event)
    }
}

extension NSWindow {
    /// Fades the window in while gliding it up a few points — quick enough to
    /// never feel slow, soft enough not to "pop".
    func presentAnimated(makeKey: Bool = true) {
        let target = frame
        alphaValue = 0
        setFrame(target.offsetBy(dx: 0, dy: -8), display: false)
        if makeKey { makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(target, display: true)
        }
    }

    /// Fades the window out, then removes it from the screen.
    func dismissAnimated(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
            completion?()
        })
    }
}
