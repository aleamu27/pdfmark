import AppKit
import PDFKit
import ApplicationServices
import ServiceManagement

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusIcon: StatusIconController!
    private var confirmPanelController: ConfirmPanelController!
    private var commentPanelController: CommentPanelController!
    private var hotkeyMonitor: Any?

    /// What the menu was built for, captured when it opens, so menu actions act
    /// on the document the user saw named at the top of the menu.
    private struct MenuState {
        let fileURL: URL
        let page: Int?
        let totalPages: Int?
        let bookmarkPage: Int?
        let commentCount: Int
        let undoLabel: String?
    }
    private var menuState: MenuState?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon (mirrors LSUIElement)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusIcon = StatusIconController()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusIcon.statusItem.menu = menu

        Toast.anchor = { [weak self] in
            guard let button = self?.statusIcon.statusItem.button, let window = button.window else { return nil }
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }

        confirmPanelController = ConfirmPanelController()
        commentPanelController = CommentPanelController()
        installGlobalHotkey()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        if AppLocation.isTranslocated {
            AppLocation.warnAboutTranslocation()
        } else if !OnboardingWindow.hasShownBefore || !AXIsProcessTrusted() {
            // First launch, or access is missing (e.g. after moving/updating the
            // app): the introduction explains what to do.
            OnboardingWindow.show()
        } else {
            // A menu-bar app has no window; show where it went after a double-click.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Toast.show("PDFMark is running — click the icon in the menu bar", systemImage: "bookmark.fill", tint: .red)
            }
        }
    }

    /// Double-clicking the app (in Finder, Launchpad, Spotlight) while it's
    /// already running: open its menu, so the click visibly does something.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DispatchQueue.main.async { [weak self] in self?.statusIcon.statusItem.button?.performClick(nil) }
        }
        return true
    }

    // MARK: - Menu

    /// Rebuilt every time it opens, so it always reflects the document currently
    /// in Preview: its name and page, whether it has a bookmark, how many
    /// comments it has, and what can be undone.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menuState = currentMenuState()

        if let state = menuState {
            menu.addItem(headerItem(
                title: state.fileURL.lastPathComponent,
                subtitle: state.page.map { page in "Page \(page)" + (state.totalPages.map { " of \($0)" } ?? "") } ?? "Open in Preview"
            ))
        } else {
            menu.addItem(headerItem(
                title: "No PDF open",
                subtitle: AXIsProcessTrusted() ? "Open a PDF in Preview to get started" : "Accessibility access needed — see Introduction"
            ))
        }
        menu.addItem(.separator())

        let hasDoc = menuState != nil
        addItem(to: menu, "Bookmark This Page", symbol: "bookmark", key: "b", action: #selector(triggerBookmarkFlow), enabled: hasDoc)
        addItem(to: menu, "Add Comment…", symbol: "text.bubble", key: "k", action: #selector(triggerCommentFlow), enabled: hasDoc)
        let count = menuState?.commentCount ?? 0
        addItem(to: menu, count > 0 ? "Show All Comments (\(count))…" : "Show All Comments…", symbol: "list.bullet.rectangle", key: "l", action: #selector(showComments), enabled: hasDoc)

        if let bookmark = menuState?.bookmarkPage {
            menu.addItem(.separator())
            addItem(to: menu, "Go to Bookmark — Page \(bookmark)", symbol: "arrow.turn.down.right", action: #selector(goToBookmark))
            addItem(to: menu, "Remove Bookmark", symbol: "bookmark.slash", action: #selector(removeBookmark))
        }

        menu.addItem(.separator())
        let undo = menuState?.undoLabel
        addItem(to: menu, undo.map { "Undo “\($0)”" } ?? "Undo", symbol: "arrow.uturn.backward", key: "z", action: #selector(undoLastChange), enabled: undo != nil)

        menu.addItem(.separator())
        let login = addItem(to: menu, "Open at Login", symbol: "power", action: #selector(toggleOpenAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        addItem(to: menu, "Show Introduction…", symbol: "questionmark.circle", action: #selector(showOnboarding))
        let quit = NSMenuItem(title: "Quit PDFMark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func currentMenuState() -> MenuState? {
        guard AXIsProcessTrusted(), let url = PreviewInspector.currentDocumentURL() else { return nil }
        var page: Int?, total: Int?
        if case .success(let context) = PreviewInspector.currentContext(), context.fileURL == url {
            page = context.guessedPage
            total = context.totalPages
        }
        let info = DocumentSummary.of(url)
        return MenuState(
            fileURL: url,
            page: page,
            totalPages: total ?? info?.pageCount,
            bookmarkPage: info?.bookmarkPage,
            commentCount: info?.commentCount ?? 0,
            undoLabel: UndoHistory.lastLabel(for: url)
        )
    }

    private func headerItem(title: String, subtitle: String) -> NSMenuItem {
        let item = NSMenuItem()
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        ])
        text.append(NSAttributedString(string: "\n" + subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        item.attributedTitle = text
        item.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil)
        item.isEnabled = false
        return item
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, symbol: String, key: String = "", action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    @objc private func toggleOpenAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                Toast.success("PDFMark won't open at login")
            } else {
                try SMAppService.mainApp.register()
                Toast.success("PDFMark will open at login")
            }
        } catch {
            report("Couldn't change the login item: \(error.localizedDescription)")
        }
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

    // MARK: - Permissions & hotkey

    /// Without Accessibility access every AX read fails (surfacing as "couldn't
    /// find Preview's window"), so say what's actually wrong instead of just
    /// flashing an error icon.
    private func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        OnboardingWindow.show()
        return false
    }

    /// ⌥⌘B, global regardless of which app is frontmost. Requires Accessibility
    /// trust (already requested above), same as the AX reads in PreviewInspector.
    /// The menu-bar icon is the primary, reliable trigger; this is a bonus for
    /// setups where the global hotkey reaches the app.
    private func installGlobalHotkey() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 11 /* B */,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.option, .command] else { return }
            self?.triggerBookmarkFlow()
        }
    }

    // MARK: - Flows

    @objc private func triggerBookmarkFlow() {
        guard ensureAccessibility() else { return }
        switch PreviewInspector.currentContext() {
        case .success(let context):
            confirmPanelController.show(
                guessedPage: context.guessedPage,
                totalPages: context.totalPages,
                onConfirm: { [weak self] page in
                    self?.modify(context.fileURL, undo: "Bookmark page \(page)", success: "Bookmarked page \(page)") {
                        try BookmarkWriter.addBookmark(to: context.fileURL, page1Indexed: page)
                        return page
                    }
                },
                onCancel: {}
            )
        case .failure(let error):
            report(error)
        }
    }

    /// Opens the comment panel with every page on screen (both halves of a
    /// two-page spread); the note starts in the right margin of the detected
    /// page at the viewport's height, and can be dragged onto any of them.
    @objc private func triggerCommentFlow() {
        guard ensureAccessibility() else { return }
        switch PreviewInspector.currentContext() {
        case .success(let context):
            guard let document = PDFDocument(url: context.fileURL),
                  let page = document.page(at: context.guessedPage - 1) else {
                report(CommentError.couldNotOpenDocument)
                return
            }
            let initial = CommentPlacement(
                page: context.guessedPage,
                point: CommentStore.defaultPoint(on: page, verticalFraction: context.viewportFraction)
            )
            commentPanelController.show(
                document: document,
                fileName: context.fileURL.lastPathComponent,
                visiblePages: context.visiblePages,
                initial: initial,
                onConfirm: { [weak self] placement, text, color in
                    self?.modify(context.fileURL, undo: "Add comment", success: "Comment added to page \(placement.page)") {
                        try CommentStore.add(to: context.fileURL, at: placement, text: text, color: color)
                        return placement.page
                    }
                },
                onCancel: {}
            )
        case .failure(let error):
            report(error)
        }
    }

    @objc private func showComments() {
        guard ensureAccessibility() else { return }
        guard let url = menuState?.fileURL ?? PreviewInspector.currentDocumentURL() else {
            report(PreviewInspectorError.noDocumentPath)
            return
        }
        CommentsWindowController.shared.show(fileURL: url, focusPage: menuState?.page)
    }

    @objc private func goToBookmark() {
        guard let state = menuState, let page = state.bookmarkPage else { return }
        PreviewInspector.showPage(page, of: state.fileURL)
    }

    @objc private func removeBookmark() {
        guard let state = menuState else { return }
        modify(state.fileURL, undo: "Remove bookmark", success: "Bookmark removed") {
            try BookmarkWriter.removeBookmark(from: state.fileURL)
            return nil
        }
    }

    @objc private func undoLastChange() {
        guard let state = menuState, let label = state.undoLabel else { return }
        modify(state.fileURL, undo: nil, success: "Undid “\(label)”") {
            try UndoHistory.undo(state.fileURL)
            return nil
        }
    }

    /// Every write goes through here: Preview is closed while the file changes,
    /// an undo snapshot is taken, the file is reopened at the right page, and the
    /// outcome is shown as a toast under the menu-bar icon.
    private func modify(_ url: URL, undo label: String?, success: String, change: @escaping () throws -> Int?) {
        PreviewInspector.modify(url, undoLabel: label, change: change) { [weak self] result in
            switch result {
            case .success:
                self?.statusIcon.flashSuccess()
                Toast.success(success)
            case .failure(let error):
                self?.report(error)
            }
            NotificationCenter.default.post(name: .pdfMarkDocumentChanged, object: url)
        }
    }

    private func report(_ error: Error) {
        report("\(error)")
    }

    private func report(_ message: String) {
        statusIcon.flashError()
        Toast.error(message)
    }
}

/// What the menu shows about a document, read with a single parse of the PDF
/// and cached until the file changes, so the menu opens instantly even for
/// large documents.
private struct DocumentSummary {
    let pageCount: Int
    let bookmarkPage: Int?
    let commentCount: Int

    private static var cache: (url: URL, stamp: Date?, size: Int?, summary: DocumentSummary)?

    static func of(_ url: URL) -> DocumentSummary? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        if let c = cache, c.url == url, c.stamp == values?.contentModificationDate, c.size == values?.fileSize {
            return c.summary
        }
        guard let document = PDFDocument(url: url) else { return nil }
        let summary = DocumentSummary(
            pageCount: document.pageCount,
            bookmarkPage: BookmarkWriter.bookmarkedPage(in: document),
            commentCount: CommentStore.comments(in: document).count
        )
        cache = (url, values?.contentModificationDate, values?.fileSize, summary)
        return summary
    }
}

/// Apps opened straight from Downloads (or a disk image) run from a random,
/// read-only location ("App Translocation"). macOS then forgets permissions
/// like Accessibility every launch, so ask the user to move the app first.
enum AppLocation {
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/") || Bundle.main.bundlePath.hasPrefix("/Volumes/")
    }

    static func warnAboutTranslocation() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move PDFMark to your Applications folder"
        alert.informativeText = "PDFMark is running from Downloads or a disk image, so macOS won't remember the Accessibility permission it needs.\n\nDrag PDFMark into the Applications folder, then open it from there."
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Show Applications Folder & Quit")
        alert.addButton(withTitle: "Continue Anyway")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            NSApp.terminate(nil)
        } else {
            OnboardingWindow.showIfNeeded()
        }
    }

    /// Quits and reopens the app, which is how macOS applies a freshly granted
    /// Accessibility permission to a running process.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
