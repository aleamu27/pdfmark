import AppKit
import PDFKit
import SwiftUI

/// Floating panel for writing a new comment. Shows the pages currently on
/// screen in Preview (e.g. a two-page spread) with a draggable note marker, a
/// color picker and the text field. A PDF note belongs to exactly one page and
/// Preview can't drag notes between pages, so this is where the page is chosen.
final class CommentPanelController {
    private var panel: ConfirmPanel?

    func show(
        document: PDFDocument,
        fileName: String,
        visiblePages: [Int],
        initial: CommentPlacement,
        onConfirm: @escaping (CommentPlacement, String, NoteColor) -> Void,
        onCancel: @escaping () -> Void
    ) {
        close()

        let size = NSSize(width: 620, height: 600)
        let panel = ConfirmPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // Dragging inside the panel moves the note, not the window.
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false

        let cancel: () -> Void = { [weak self] in
            self?.close()
            onCancel()
        }
        let visible = visiblePages.filter { $0 >= 1 && $0 <= document.pageCount }
        panel.contentView = NSHostingView(rootView: NewCommentView(
            thumbnails: PageThumbnails(document: document),
            existing: CommentStore.comments(in: document),
            fileName: fileName,
            size: size,
            spread: visible.isEmpty ? [initial.page] : visible,
            placement: initial,
            onConfirm: { [weak self] placement, text, color in
                self?.close()
                onConfirm(placement, text, color)
            },
            onCancel: cancel
        ))
        panel.onCancel = cancel

        panel.center()
        panel.presentAnimated()
        self.panel = panel
    }

    func close() {
        panel?.dismissAnimated()
        panel = nil
    }
}

private struct NewCommentView: View {
    let thumbnails: PageThumbnails
    let existing: [CommentRecord]
    let fileName: String
    let size: NSSize
    @State var spread: [Int]
    @State var placement: CommentPlacement
    let onConfirm: (CommentPlacement, String, NoteColor) -> Void
    let onCancel: () -> Void

    @AppStorage("PDFMarkLastNoteColor") private var colorRaw = NoteColor.yellow.rawValue
    @State private var text = ""
    @FocusState private var textFocused: Bool

    private var color: NoteColor { NoteColor(rawValue: colorRaw) ?? .yellow }
    private var canSubmit: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            PagePickerCard(
                thumbnails: thumbnails,
                spread: $spread,
                placement: $placement,
                color: color,
                otherNotes: existing,
                height: 290
            )

            CommentEditor(text: $text, focused: $textFocused, placeholder: "Write your comment…")
                .frame(minHeight: 96)

            HStack(spacing: 12) {
                NoteColorPicker(selection: Binding(get: { color }, set: { colorRaw = $0.rawValue }))
                Spacer()
                Text("⌘↩ Add  ·  esc Cancel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Comment") { onConfirm(placement, text, color) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
            .controlSize(.regular)
        }
        .padding(20)
        .frame(width: size.width, height: size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .onAppear { DispatchQueue.main.async { textFocused = true } }
        .onExitCommand(perform: onCancel)
    }

    private var header: some View {
        HStack(spacing: 12) {
            NoteBadge(color: color, size: 38)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .animation(.easeInOut(duration: 0.2), value: color)
            VStack(alignment: .leading, spacing: 1) {
                Text("New Comment on Page \(placement.page)")
                    .font(.system(size: 15, weight: .semibold))
                Text(fileName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel (esc)")
        }
    }
}

/// Multi-line text field with placeholder, styled like a native input.
struct CommentEditor: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13.5))
            .lineSpacing(2)
            .focused(focused)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused.wrappedValue ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: focused.wrappedValue ? 2 : 1)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
    }
}
