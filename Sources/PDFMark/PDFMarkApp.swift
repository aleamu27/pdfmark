import AppKit
import ApplicationServices

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusIcon: StatusIconController!
    private var confirmPanelController: ConfirmPanelController!
    private var hotkeyMonitor: Any?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon (mirrors LSUIElement)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusIcon = StatusIconController()
        statusIcon.statusItem.button?.target = self
        statusIcon.statusItem.button?.action = #selector(statusItemClicked)
        statusIcon.statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        confirmPanelController = ConfirmPanelController()
        requestAccessibilityPermissionIfNeeded()
        installGlobalHotkey()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        OnboardingWindow.showIfNeeded()
    }

    /// Left click on the status item triggers the bookmark flow; right click
    /// shows a small menu (re-open the intro, quit — there's otherwise no way to
    /// quit a menu-bar-only app).
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusItemMenu()
        } else {
            triggerBookmarkFlow()
        }
    }

    private func showStatusItemMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Introduction…", action: #selector(showOnboarding), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PDFMark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusIcon.statusItem.menu = menu
        statusIcon.statusItem.button?.performClick(nil)
        statusIcon.statusItem.menu = nil
    }

    @objc private func showOnboarding() {
        OnboardingWindow.show()
    }

    /// Entry point for the "Set PDF Bookmark Here" macOS Service, which shows up
    /// under the Services submenu in any app's right-click menu — including
    /// Preview's, as seen in the standard text-selection context menu. Native
    /// third-party apps can't inject a flat top-level item into another app's
    /// context menu (no public API for that); Services are the sanctioned way to
    /// reach that menu at all.
    @objc func addBookmarkService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        DispatchQueue.main.async { [weak self] in
            self?.triggerBookmarkFlow()
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        appendDebugLog("launch trusted(prompt)=\(trusted)")
        appendDebugLog("launch trusted(plain)=\(AXIsProcessTrusted())")

        for delay in [1, 2, 3, 5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) {
                self.appendDebugLog("+\(delay)s trusted(plain)=\(AXIsProcessTrusted())")
            }
        }
    }

    private func appendDebugLog(_ message: String) {
        let line = "\(message)\n"
        let path = "/tmp/pdfmark_debug.log"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// ⌥⌘B, global regardless of which app is frontmost. Requires Accessibility
    /// trust (already requested above), same as the AX reads in PreviewInspector.
    /// The status item icon also triggers the same flow on click, as a fallback
    /// for setups where the global hotkey doesn't reach the app (e.g. a modifier
    /// key remapping or third-party tool already claiming the combo).
    private func installGlobalHotkey() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 11 /* B */,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.option, .command] else { return }
            self?.triggerBookmarkFlow()
        }
    }

    @objc private func triggerBookmarkFlow() {
        switch PreviewInspector.currentContext() {
        case .success(let context):
            confirmPanelController.show(
                guessedPage: context.guessedPage,
                totalPages: context.totalPages,
                onConfirm: { [weak self] page in
                    self?.writeBookmark(fileURL: context.fileURL, page: page)
                },
                onCancel: {}
            )
        case .failure(let error):
            try? "\(error)".write(toFile: "/tmp/pdfmark_debug.log", atomically: true, encoding: .utf8)
            statusIcon.flashError()
        }
    }

    private func writeBookmark(fileURL: URL, page: Int) {
        do {
            try BookmarkWriter.addBookmark(to: fileURL, page1Indexed: page)
            statusIcon.flashSuccess()
            // Give Preview a moment to notice the external file change and reload
            // before asking it to scroll — otherwise we might act on page elements
            // from just before the reload.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PreviewInspector.scrollToPage(page)
            }
        } catch {
            try? "\(error)".write(toFile: "/tmp/pdfmark_debug.log", atomically: true, encoding: .utf8)
            statusIcon.flashError()
        }
    }
}
