import ApplicationServices
import AppKit
import Foundation

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(el, name as CFString, &value)
    return err == .success ? value : nil
}

func dump(_ el: AXUIElement, depth: Int, maxDepth: Int, path: String) {
    guard depth <= maxDepth else { return }
    let indent = String(repeating: "  ", count: depth)

    let role = (attr(el, kAXRoleAttribute) as? String) ?? "?"
    let subrole = (attr(el, kAXSubroleAttribute) as? String) ?? ""
    let title = (attr(el, kAXTitleAttribute) as? String) ?? ""
    let value = attr(el, kAXValueAttribute)
    let valueDesc = (attr(el, kAXValueDescriptionAttribute) as? String) ?? ""
    let desc = (attr(el, kAXDescriptionAttribute) as? String) ?? ""
    let placeholder = (attr(el, "AXPlaceholderValue") as? String) ?? ""

    var valueStr = ""
    if let v = value {
        if let s = v as? String { valueStr = s }
        else if let n = v as? NSNumber { valueStr = n.stringValue }
        else { valueStr = "\(v)" }
    }

    var line = "\(indent)[\(path)] role=\(role)"
    if !subrole.isEmpty { line += " subrole=\(subrole)" }
    if !title.isEmpty { line += " title=\"\(title)\"" }
    if !valueStr.isEmpty { line += " value=\"\(valueStr)\"" }
    if !valueDesc.isEmpty { line += " valueDesc=\"\(valueDesc)\"" }
    if !desc.isEmpty { line += " desc=\"\(desc)\"" }
    if !placeholder.isEmpty { line += " placeholder=\"\(placeholder)\"" }
    print(line)

    guard let childrenRef = attr(el, kAXChildrenAttribute) else { return }
    guard let children = childrenRef as? [AXUIElement] else { return }
    for (i, child) in children.enumerated() {
        dump(child, depth: depth + 1, maxDepth: maxDepth, path: "\(path).\(i)")
    }
}

// --- main ---
guard AXIsProcessTrusted() else {
    print("NOT TRUSTED: grant Accessibility permission to this terminal app first.")
    exit(1)
}

guard let preview = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Preview" }) else {
    print("Preview is not running.")
    exit(1)
}

print("Preview pid: \(preview.processIdentifier)")
let appEl = AXUIElementCreateApplication(preview.processIdentifier)

var focusedWindow: AnyObject?
let werr = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focusedWindow)
guard werr == .success, let winRef = focusedWindow else {
    print("Could not get focused window, err=\(werr.rawValue)")
    // fallback: list all windows
    if let windowsRef = attr(appEl, kAXWindowsAttribute), let windows = windowsRef as? [AXUIElement] {
        print("Found \(windows.count) window(s) via AXWindows, dumping first.")
        if let first = windows.first {
            let doc = attr(first, kAXDocumentAttribute) as? String ?? "?"
            print("AXDocument: \(doc)")
            dump(first, depth: 0, maxDepth: 12, path: "0")
        }
    }
    exit(1)
}

let win = winRef as! AXUIElement
let doc = attr(win, kAXDocumentAttribute) as? String ?? "?"
print("AXDocument: \(doc)")
print("---- FULL AX TREE (focused window) ----")
dump(win, depth: 0, maxDepth: 14, path: "0")
