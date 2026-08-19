import ApplicationServices
import AppKit
import Foundation

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(el, name as CFString, &value)
    return err == .success ? value : nil
}

guard let preview = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Preview" }) else {
    print("Preview not running"); exit(1)
}
let appEl = AXUIElementCreateApplication(preview.processIdentifier)
var focusedWindow: AnyObject?
let werr = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focusedWindow)
guard werr == .success, let winRef = focusedWindow else {
    print("no focused window err=\(werr.rawValue)"); exit(1)
}
let win = winRef as! AXUIElement
let title = (attr(win, kAXTitleAttribute) as? String) ?? "?"
let doc = attr(win, kAXDocumentAttribute) as? String ?? "?"
print("TITLE: \(title)")
print("DOC: \(doc)")
