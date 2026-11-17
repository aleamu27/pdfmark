import AppKit
import ApplicationServices
import Foundation

enum PreviewInspectorError: Error, CustomStringConvertible {
    case previewNotRunning
    case noFocusedWindow
    case noDocumentPath
    case pageGuessFailed
    case previewWouldNotClose

    var description: String {
        switch self {
        case .previewNotRunning: return "Preview isn't running (open a PDF in Preview first)"
        case .noFocusedWindow: return "Couldn't find Preview's window"
        case .noDocumentPath: return "Couldn't find the document's file path"
        case .pageGuessFailed: return "Couldn't guess the page number"
        case .previewWouldNotClose: return "Preview is asking about unsaved changes — answer it, then try again"
        }
    }
}

struct PreviewContext {
    let fileURL: URL
    let guessedPage: Int // 1-indexed
    let totalPages: Int
    /// Which part of the guessed page sits at the middle of Preview's viewport,
    /// as a fraction of the page height (0 = top edge, 1 = bottom edge).
    let viewportFraction: CGFloat?
    /// All pages currently on screen (1-indexed), e.g. both halves of a two-page
    /// spread. Always contains `guessedPage`.
    let visiblePages: [Int]
}

enum PreviewInspector {
    private static let previewBundleID = "com.apple.Preview"

    /// Preview is looked up directly among running apps rather than requiring it
    /// to be the frontmost application. The only trigger is a click on our own
    /// menu-bar status item, which makes *this* app frontmost — so a
    /// "must be frontmost" check would never see Preview. AX attributes are
    /// readable regardless of which app is active once Accessibility is granted.
    private static func previewApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: previewBundleID).first
    }

    static func currentContext() -> Result<PreviewContext, PreviewInspectorError> {
        guard let preview = previewApp() else {
            return .failure(.previewNotRunning)
        }

        let appEl = AXUIElementCreateApplication(preview.processIdentifier)
        guard let window = focusedWindow(of: appEl) else {
            return .failure(.noFocusedWindow)
        }

        guard let fileURL = documentURL(of: window) else {
            return .failure(.noDocumentPath)
        }

        guard let guess = guessCurrentPage(in: window) else {
            return .failure(.pageGuessFailed)
        }

        return .success(PreviewContext(fileURL: fileURL, guessedPage: guess.page, totalPages: guess.total, viewportFraction: guess.fraction, visiblePages: guess.visible))
    }

    /// The PDF open in Preview's front window, without needing a page.
    static func currentDocumentURL() -> URL? {
        guard let preview = previewApp() else { return nil }
        let appEl = AXUIElementCreateApplication(preview.processIdentifier)
        return focusedWindow(of: appEl).flatMap(documentURL(of:))
    }

    /// The text currently selected in Preview's front window, with the page it's
    /// on and the screen positions of its first/last characters (translated to
    /// page-relative coordinates) so the exact occurrence can be highlighted.
    /// Only looks at pages on screen; a selection spanning pages uses the first.
    static func currentSelection() -> TextSelection? {
        guard let preview = previewApp() else { return nil }
        let appEl = AXUIElementCreateApplication(preview.processIdentifier)
        guard let window = focusedWindow(of: appEl), let fileURL = documentURL(of: window),
              let pages = contentPages(in: window)?.pages, !pages.isEmpty else { return nil }

        for index in visiblePageIndices(pages) {
            let pageElement = pages[index]
            guard let text = attribute(pageElement, kAXSelectedTextAttribute) as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            var selection = TextSelection(fileURL: fileURL, page: index + 1, text: text)
            if let pagePos = position(pageElement), let pageSize = size(pageElement), pageSize.width > 0, pageSize.height > 0 {
                func normalized(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: (p.x - pagePos.x) / pageSize.width, y: (p.y - pagePos.y) / pageSize.height)
                }
                let runs = findAll(pageElement, matching: { role($0) == "AXStaticText" }, maxDepth: 12)
                    .compactMap { el -> (AXUIElement, CFRange)? in
                        guard let r = selectedRange(of: el), r.length > 0 else { return nil }
                        return (el, r)
                    }
                if let (first, r) = runs.first, let rect = bounds(of: CFRange(location: r.location, length: 1), in: first) {
                    selection.start = normalized(CGPoint(x: rect.minX + 0.5, y: rect.midY))
                }
                if let (last, r) = runs.last, let rect = bounds(of: CFRange(location: r.location + r.length - 1, length: 1), in: last) {
                    selection.end = normalized(CGPoint(x: rect.maxX - 0.5, y: rect.midY))
                }
            }
            return selection
        }
        return nil
    }

    private static func visiblePageIndices(_ pages: [AXUIElement]) -> [Int] {
        if let container = attribute(pages[0], kAXParentAttribute).map({ $0 as! AXUIElement }),
           let visible = attribute(container, kAXVisibleChildrenAttribute) as? [AXUIElement] {
            let indices = visible.compactMap { v in pages.firstIndex(where: { CFEqual($0, v) }) }.sorted()
            if !indices.isEmpty { return indices }
        }
        return Array(pages.indices)
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var out: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, param, &out) == .success,
              let value = out else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        return rect
    }

    /// Changes the PDF on disk safely and shows the result right away:
    /// 1. closes Preview's window for the file — Preview saves any edits of its
    ///    own first, so neither side overwrites the other's changes;
    /// 2. stores an undo snapshot (if `undoLabel` is given) and runs `change`;
    /// 3. reopens the file in Preview at the page `change` returns, or at the
    ///    page the reader was on.
    /// If Preview doesn't have the file open, the change is simply applied.
    /// Asynchronous; polls on the main run loop without blocking.
    static func modify(
        _ fileURL: URL,
        undoLabel: String?,
        activatePreview: Bool = true,
        change: @escaping () throws -> Int?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        func apply() -> (Result<Void, Error>, Int?) {
            do {
                if let undoLabel { try UndoHistory.snapshot(fileURL, label: undoLabel) }
                do {
                    let page = try change()
                    return (.success(()), page)
                } catch {
                    if undoLabel != nil { UndoHistory.discardLatest(fileURL) }
                    throw error
                }
            } catch {
                return (.failure(error), nil)
            }
        }

        guard let preview = previewApp() else {
            completion(apply().0)
            return
        }
        let appEl = AXUIElementCreateApplication(preview.processIdentifier)
        guard let openWindow = window(showing: fileURL, in: appEl),
              let close = attribute(openWindow, kAXCloseButtonAttribute) else {
            completion(apply().0)
            return
        }

        let previousPage = guessCurrentPage(in: openWindow)?.page
        AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString)
        poll(timeout: 8, until: { window(showing: fileURL, in: appEl) == nil }) { closed in
            guard closed else {
                completion(.failure(PreviewInspectorError.previewWouldNotClose))
                return
            }
            let (result, page) = apply()
            reopen(fileURL, in: preview, appElement: appEl, atPage: page ?? previousPage, activate: activatePreview)
            completion(result)
        }
    }

    /// Brings Preview forward and scrolls its window for `fileURL` to a page.
    static func showPage(_ page1Indexed: Int, of fileURL: URL) {
        guard let preview = previewApp() else {
            NSWorkspace.shared.open(fileURL)
            return
        }
        let appEl = AXUIElementCreateApplication(preview.processIdentifier)
        guard let window = window(showing: fileURL, in: appEl) else {
            reopen(fileURL, in: preview, appElement: appEl, atPage: page1Indexed, activate: true)
            return
        }
        preview.activate()
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if let pages = contentPages(in: window)?.pages, pages.indices.contains(page1Indexed - 1) {
            AXUIElementPerformAction(pages[page1Indexed - 1], "AXScrollToVisible" as CFString)
        }
    }

    private static func reopen(_ fileURL: URL, in preview: NSRunningApplication, appElement: AXUIElement, atPage page1Indexed: Int?, activate: Bool) {
        guard let previewURL = preview.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activate
        NSWorkspace.shared.open([fileURL], withApplicationAt: previewURL, configuration: config)

        guard let page1Indexed else { return }
        var pages: [AXUIElement] = []
        poll(timeout: 6, until: {
            guard let w = window(showing: fileURL, in: appElement), let found = contentPages(in: w)?.pages else { return false }
            pages = found
            return !pages.isEmpty
        }) { _ in
            guard pages.indices.contains(page1Indexed - 1) else { return }
            // Give Preview a beat to finish laying out before scrolling.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                AXUIElementPerformAction(pages[page1Indexed - 1], "AXScrollToVisible" as CFString)
            }
        }
    }

    private static func window(showing fileURL: URL, in appElement: AXUIElement) -> AXUIElement? {
        let target = fileURL.standardizedFileURL.path
        let windows = (attribute(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.first { documentURL(of: $0)?.standardizedFileURL.path == target }
    }

    private static func poll(timeout: TimeInterval, until done: @escaping () -> Bool, then next: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func tick() {
            if done() { next(true); return }
            if Date() > deadline { next(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: tick)
        }
        tick()
    }

    // MARK: - AX helpers

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }

    /// `kAXFocusedWindowAttribute` can come back empty even while Preview is the
    /// frontmost app (observed in practice — e.g. right after activating Preview
    /// via something other than a direct click, like our own status item). Falls
    /// back to the main window, then simply the first window, before giving up.
    private static func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        if let value = attribute(appElement, kAXFocusedWindowAttribute) {
            return (value as! AXUIElement)
        }
        if let value = attribute(appElement, kAXMainWindowAttribute) {
            return (value as! AXUIElement)
        }
        if let windows = attribute(appElement, kAXWindowsAttribute) as? [AXUIElement], let first = windows.first {
            return first
        }
        return nil
    }

    private static func documentURL(of window: AXUIElement) -> URL? {
        guard let path = attribute(window, kAXDocumentAttribute) as? String else { return nil }
        return URL(string: path)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func role(_ element: AXUIElement) -> String {
        (attribute(element, kAXRoleAttribute) as? String) ?? ""
    }

    private static func position(_ element: AXUIElement) -> CGPoint? {
        guard let value = attribute(element, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private static func size(_ element: AXUIElement) -> CGSize? {
        guard let value = attribute(element, kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        AXValueGetValue(axValue, .cgSize, &s)
        return s
    }

    private static func findAll(_ element: AXUIElement, matching predicate: (AXUIElement) -> Bool, depth: Int = 0, maxDepth: Int = 12) -> [AXUIElement] {
        guard depth <= maxDepth else { return [] }
        var results: [AXUIElement] = []
        if predicate(element) { results.append(element) }
        for child in children(element) {
            results.append(contentsOf: findAll(child, matching: predicate, depth: depth + 1, maxDepth: maxDepth))
        }
        return results
    }

    /// Finds the AXScrollArea that hosts the document's AXPage elements (as opposed
    /// to the thumbnail sidebar's own scroll area, which doesn't contain AXPage
    /// children), returning it alongside the pages in document order.
    private static func contentPages(in window: AXUIElement) -> (scrollArea: AXUIElement, pages: [AXUIElement])? {
        let scrollAreas = findAll(window, matching: { role($0) == "AXScrollArea" })
        for scrollArea in scrollAreas {
            let pages = findAll(scrollArea, matching: { role($0) == "AXPage" }, maxDepth: 6)
            if !pages.isEmpty {
                return (scrollArea, pages)
            }
        }
        return nil
    }

    /// Guesses the current page. Preview exposes the pages actually on screen via
    /// the document container's `AXVisibleChildren`; this is the reliable signal
    /// (on recent macOS, off-screen AXPage elements all report the same bogus
    /// position, so pure geometry over every page always lands on page 1). Among
    /// the visible pages, the one straddling the viewport's vertical center wins;
    /// in two-page view, where both pages tie, the left (lower-numbered) one does.
    /// If Preview doesn't provide visible children, falls back to geometry over
    /// all pages.
    private static func guessCurrentPage(in window: AXUIElement) -> (page: Int, total: Int, fraction: CGFloat?, visible: [Int])? {
        guard let (scrollArea, pages) = contentPages(in: window),
              let areaPos = position(scrollArea), let areaSize = size(scrollArea) else { return nil }

        var candidates = Array(pages.indices)
        var haveVisible = false
        if let container = attribute(pages[0], kAXParentAttribute).map({ $0 as! AXUIElement }),
           let visible = attribute(container, kAXVisibleChildrenAttribute) as? [AXUIElement] {
            let visibleIndices = visible.compactMap { v in pages.firstIndex(where: { CFEqual($0, v) }) }.sorted()
            if !visibleIndices.isEmpty { candidates = visibleIndices; haveVisible = true }
        }

        let viewportCenterY = areaPos.y + areaSize.height / 2
        var best: (index: Int, distance: CGFloat, fraction: CGFloat?)?

        for index in candidates {
            guard let pos = position(pages[index]), let sz = size(pages[index]) else {
                if best == nil { best = (index, .greatestFiniteMagnitude, nil) }
                continue
            }
            let distance = abs(pos.y + sz.height / 2 - viewportCenterY)
            if best == nil || distance < best!.distance - 0.5 {
                // AX coordinates are top-left based, so this is 0 at the page's top edge.
                let fraction = sz.height > 0 ? min(max((viewportCenterY - pos.y) / sz.height, 0), 1) : nil
                best = (index, distance, fraction)
            }
        }

        return best.map { best in
            let visible = haveVisible ? candidates.map { $0 + 1 } : [best.index + 1]
            return (best.index + 1, pages.count, best.fraction, visible)
        }
    }
}
