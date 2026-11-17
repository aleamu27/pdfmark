import AppKit
import SwiftUI

/// A borderless, non-activating floating panel that lets the user confirm or edit
/// the guessed page number before a bookmark is written. Escape cancels via
/// `cancelOperation`, which AppKit routes here automatically when the panel's
/// first responder doesn't handle it itself.
final class ConfirmPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        EditingShortcuts.handle(event, from: self) || super.performKeyEquivalent(with: event)
    }
}

extension NSPanel {
    /// Places the panel just below-right of the mouse, clamped to the screen.
    func positionNearMouse() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            center()
            return
        }

        var origin = CGPoint(x: mouseLocation.x + 12, y: mouseLocation.y - frame.height - 12)
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        setFrameOrigin(origin)
    }
}

final class ConfirmPanelController {
    private var panel: ConfirmPanel?
    private var autoCloseTimer: Timer?
    private let autoCloseInterval: TimeInterval = 8

    func show(guessedPage: Int, totalPages: Int, onConfirm: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        close()

        let state = ConfirmPanelState(page: guessedPage, totalPages: totalPages)

        let panel = ConfirmPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 148),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false

        let content = ConfirmPanelView(
            state: state,
            onConfirm: { [weak self] page in
                self?.close()
                onConfirm(page)
            },
            onCancel: { [weak self] in
                self?.close()
                onCancel()
            },
            onUserActivity: { [weak self] in
                self?.resetAutoCloseTimer(onCancel: onCancel)
            }
        )
        panel.contentView = NSHostingView(rootView: content)
        panel.onCancel = { [weak self] in
            self?.close()
            onCancel()
        }

        panel.positionNearMouse()
        panel.presentAnimated()

        self.panel = panel
        resetAutoCloseTimer(onCancel: onCancel)
    }

    func close() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        panel?.dismissAnimated()
        panel = nil
    }

    private func resetAutoCloseTimer(onCancel: @escaping () -> Void) {
        autoCloseTimer?.invalidate()
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: autoCloseInterval, repeats: false) { [weak self] _ in
            self?.close()
            onCancel()
        }
    }
}

private final class ConfirmPanelState: ObservableObject {
    @Published var pageText: String
    let totalPages: Int

    init(page: Int, totalPages: Int) {
        self.pageText = String(page)
        self.totalPages = totalPages
    }
}

private struct ConfirmPanelView: View {
    @ObservedObject fileprivate var state: ConfirmPanelState
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void
    let onUserActivity: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Bookmark page")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                TextField("", text: $state.pageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .focused($fieldFocused)
                    .onSubmit { confirm() }

                Text("/ \(state.totalPages)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Button("Add") { confirm() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 220, height: 148)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .overlay(alignment: .topTrailing) {
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .onAppear {
            fieldFocused = true
            selectAllText()
        }
        .onChange(of: state.pageText) { _ in onUserActivity() }
    }

    private func confirm() {
        guard let page = Int(state.pageText), page >= 1, page <= state.totalPages else { return }
        onConfirm(page)
    }

    private func selectAllText() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                editor.selectAll(nil)
            }
        }
    }
}
