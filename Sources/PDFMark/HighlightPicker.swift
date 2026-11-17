import AppKit
import SwiftUI

/// A compact color picker that pops up at the mouse after "Highlight with
/// PDFMark": click a color (or press 1–5, ↩ for the last one used, esc to cancel).
final class HighlightPickerController {
    private var panel: ConfirmPanel?
    private var keyMonitor: Any?

    func show(onPick: @escaping (HighlightColor) -> Void, onCancel: @escaping () -> Void = {}) {
        close()

        let last = HighlightColor(rawValue: UserDefaults.standard.string(forKey: "PDFMarkLastHighlightColor") ?? "") ?? .yellow
        let pick: (HighlightColor) -> Void = { [weak self] color in
            UserDefaults.standard.set(color.rawValue, forKey: "PDFMarkLastHighlightColor")
            self?.close()
            onPick(color)
        }
        let cancel: () -> Void = { [weak self] in
            self?.close()
            onCancel()
        }

        let host = NSHostingView(rootView: HighlightPickerView(last: last, onPick: pick, onCancel: cancel))
        host.frame.size = host.fittingSize

        let panel = ConfirmPanel(contentRect: host.frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.onCancel = cancel
        panel.positionNearMouse()
        panel.presentAnimated()
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === panel else { return event }
            switch event.keyCode {
            case 53: cancel(); return nil                // esc
            case 36, 76: pick(last); return nil          // return / enter
            default:
                if let n = Int(event.charactersIgnoringModifiers ?? ""), (1...HighlightColor.allCases.count).contains(n) {
                    pick(HighlightColor.allCases[n - 1])
                    return nil
                }
                return event
            }
        }
    }

    func close() {
        keyMonitor.map(NSEvent.removeMonitor)
        keyMonitor = nil
        panel?.dismissAnimated()
        panel = nil
    }
}

private struct HighlightPickerView: View {
    let last: HighlightColor
    let onPick: (HighlightColor) -> Void
    let onCancel: () -> Void
    @State private var hovered: HighlightColor?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "highlighter")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(HighlightColor.allCases.enumerated()), id: \.element) { index, color in
                Button { onPick(color) } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().strokeBorder(color == last ? Color.accentColor : .clear, lineWidth: 2))
                        .scaleEffect(hovered == color ? 1.15 : 1)
                        .animation(.easeOut(duration: 0.1), value: hovered)
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? color : (hovered == color ? nil : hovered) }
                .help("\(color.name) (\(index + 1))")
            }
            Divider().frame(height: 22)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel (esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(14)
    }
}
