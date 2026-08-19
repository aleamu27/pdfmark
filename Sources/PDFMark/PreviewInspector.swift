import AppKit
import ApplicationServices
import Foundation

enum PreviewInspectorError: Error, CustomStringConvertible {
    case previewNotRunning
    case noFocusedWindow
    case noDocumentPath
    case pageGuessFailed

    var description: String {
        switch self {
        case .previewNotRunning: return "Preview isn't running (open a PDF in Preview first)"
        case .noFocusedWindow: return "Couldn't find Preview's window"
        case .noDocumentPath: return "Couldn't find the document's file path"
        case .pageGuessFailed: return "Couldn't guess the page number"
        }
    }
}

struct PreviewContext {
    let fileURL: URL
    let guessedPage: Int // 1-indexed
    let totalPages: Int
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

        guard let (page, total) = guessCurrentPage(in: window) else {
            return .failure(.pageGuessFailed)
        }

        return .success(PreviewContext(fileURL: fileURL, guessedPage: page, totalPages: total))
    }

    /// Scrolls Preview's currently focused window so the given 1-indexed page is
    /// visible, using the accessibility "scroll to visible" action rather than
    /// simulating scroll events. Best-effort: silently does nothing if Preview
    /// isn't frontmost or the page can't be located.
    static func scrollToPage(_ page1Indexed: Int) {
        guard let preview = previewApp() else { return }
        let appEl = AXUIElementCreateApplication(preview.processIdentifier)
        guard let window = focusedWindow(of: appEl) else { return }
        guard let (_, pages) = contentPages(in: window) else { return }

        let index = page1Indexed - 1
        guard index >= 0, index < pages.count else { return }
        AXUIElementPerformAction(pages[index], "AXScrollToVisible" as CFString)
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

    /// Guesses the currently visible page by locating which page overlaps the
    /// vertical center of the content scroll area's visible frame. This is robust
    /// to sidebar visibility and window resizing, unlike the window title (which
    /// only briefly reflects the current page after a scroll event and otherwise
    /// reverts to a stale value).
    private static func guessCurrentPage(in window: AXUIElement) -> (page: Int, total: Int)? {
        guard let (scrollArea, pages) = contentPages(in: window),
              let areaPos = position(scrollArea), let areaSize = size(scrollArea) else { return nil }

        let viewportCenterY = areaPos.y + areaSize.height / 2
        var best: (index: Int, distance: CGFloat)?

        for (index, pageElement) in pages.enumerated() {
            guard let pos = position(pageElement), let sz = size(pageElement) else { continue }
            let pageCenterY = pos.y + sz.height / 2
            let distance = abs(pageCenterY - viewportCenterY)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }

        return best.map { ($0.index + 1, pages.count) }
    }
}
