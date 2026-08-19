import ApplicationServices
import AppKit
import Foundation

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(el, name as CFString, &value)
    return err == .success ? value : nil
}

func role(_ el: AXUIElement) -> String { (attr(el, kAXRoleAttribute) as? String) ?? "" }
func subrole(_ el: AXUIElement) -> String { (attr(el, kAXSubroleAttribute) as? String) ?? "" }
func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}
func position(_ el: AXUIElement) -> CGPoint? {
    guard let v = attr(el, kAXPositionAttribute) else { return nil }
    var p = CGPoint.zero
    guard AXValueGetType(v as! AXValue) == .cgPoint else { return nil }
    AXValueGetValue(v as! AXValue, .cgPoint, &p)
    return p
}
func size(_ el: AXUIElement) -> CGSize? {
    guard let v = attr(el, kAXSizeAttribute) else { return nil }
    var s = CGSize.zero
    guard AXValueGetType(v as! AXValue) == .cgSize else { return nil }
    AXValueGetValue(v as! AXValue, .cgSize, &s)
    return s
}

// find first descendant matching predicate (BFS)
func findAll(_ el: AXUIElement, _ predicate: (AXUIElement) -> Bool, results: inout [AXUIElement], depth: Int = 0, maxDepth: Int = 12) {
    guard depth <= maxDepth else { return }
    if predicate(el) { results.append(el) }
    for c in children(el) {
        findAll(c, predicate, results: &results, depth: depth + 1, maxDepth: maxDepth)
    }
}

guard AXIsProcessTrusted() else { print("not trusted"); exit(1) }
guard let preview = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Preview" }) else {
    print("Preview not running"); exit(1)
}
let appEl = AXUIElementCreateApplication(preview.processIdentifier)
var focusedWindow: AnyObject?
let werr = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focusedWindow)
guard werr == .success, let winRef = focusedWindow else { print("no window"); exit(1) }
let win = winRef as! AXUIElement

// Find the AXScrollArea that contains AXPage descendants (the main content scroll area)
var scrollAreas: [AXUIElement] = []
findAll(win, { role($0) == "AXScrollArea" }, results: &scrollAreas)

var contentScrollArea: AXUIElement?
var pages: [AXUIElement] = []
for sa in scrollAreas {
    var found: [AXUIElement] = []
    findAll(sa, { role($0) == "AXPage" }, results: &found, maxDepth: 6)
    if !found.isEmpty {
        contentScrollArea = sa
        pages = found
        break
    }
}

guard let sa = contentScrollArea else { print("no content scroll area with AXPage found"); exit(1) }
guard let saPos = position(sa), let saSize = size(sa) else { print("no geometry for scroll area"); exit(1) }
let viewportCenterY = saPos.y + saSize.height / 2

print("Scroll area frame: pos=\(saPos) size=\(saSize), viewportCenterY=\(viewportCenterY)")
print("Found \(pages.count) AXPage elements")

var best: (index: Int, dist: CGFloat)? = nil
for (i, p) in pages.enumerated() {
    guard let pos = position(p), let sz = size(p) else { continue }
    let pageCenterY = pos.y + sz.height / 2
    let overlaps = (pos.y <= viewportCenterY) && (pos.y + sz.height >= viewportCenterY)
    let dist = abs(pageCenterY - viewportCenterY)
    print("  page[\(i)] pos=\(pos) size=\(sz) overlapsCenter=\(overlaps) distToCenter=\(dist)")
    if best == nil || dist < best!.dist {
        best = (i, dist)
    }
}

if let b = best {
    print("BEST GUESS page index (0-based): \(b.index) -> 1-based page number: \(b.index + 1)")
}
