import AppKit
import SwiftUI

/// A small, self-dismissing confirmation bubble just below the menu-bar icon
/// ("Comment added to page 92", or what went wrong). Never takes focus and
/// ignores the mouse, so it can't get in the way.
enum Toast {
    /// Screen rect to hang the toast from (the status item's button).
    static var anchor: (() -> NSRect?)?

    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func success(_ message: String) {
        show(message, systemImage: "checkmark.circle.fill", tint: .green)
    }

    static func error(_ message: String) {
        show(message, systemImage: "exclamationmark.triangle.fill", tint: .orange, duration: 5)
    }

    static func show(_ message: String, systemImage: String, tint: Color, duration: TimeInterval = 2.5) {
        hideWork?.cancel()
        panel?.dismissAnimated()

        let host = NSHostingView(rootView: ToastView(message: message, systemImage: systemImage, tint: tint))
        host.frame.size = host.fittingSize

        let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let size = host.frame.size
        if let anchor = anchor?(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: visible.maxY - size.height - 6))
        } else if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 6))
        }

        // Drop down from under the menu bar, then float back up as it fades.
        let rest = panel.frame
        panel.alphaValue = 0
        panel.setFrame(rest.offsetBy(dx: 0, dy: 10), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(rest, display: true)
        }
        self.panel = panel

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                panel.animator().setFrame(rest.offsetBy(dx: 0, dy: 6), display: true)
            }) {
                panel.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

private struct ToastView: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .padding(10)
    }
}
