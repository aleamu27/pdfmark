import AppKit
import PDFKit
import SwiftUI

extension Notification.Name {
    /// Posted (object: file URL) after PDFMark changes a PDF, so open windows refresh.
    static let pdfMarkDocumentChanged = Notification.Name("PDFMarkDocumentChanged")
}

/// The comments window: every note in the document, grouped by page and
/// searchable, with an inspector to edit the text, change the color, move the
/// note (to any page), jump to it in Preview, or delete it. Includes notes made
/// in Preview, not just PDFMark's own.
final class CommentsWindowController: NSObject, NSWindowDelegate {
    static let shared = CommentsWindowController()

    private var window: EditingWindow?
    private var model: CommentsModel?

    func show(fileURL: URL, focusPage: Int?) {
        if let model, let window, model.fileURL == fileURL {
            model.reload()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        window?.close()

        let model = CommentsModel(fileURL: fileURL, focusPage: focusPage)
        let window = EditingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Comments — \(fileURL.lastPathComponent)"
        window.representedURL = fileURL
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 560)
        window.contentView = NSHostingView(rootView: CommentsView(model: model))
        window.setFrameAutosaveName("PDFMarkCommentsWindow")
        if !window.setFrameUsingName("PDFMarkCommentsWindow") { window.center() }
        window.delegate = self
        window.onDeleteKey = { [weak model] in model?.requestDeleteSelected() }

        self.model = model
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Don't start with the cursor in the search field: then ⌫ would edit the
        // search text instead of offering to delete the selected comment.
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model?.reloadIfChangedOnDisk()
    }

    func windowWillClose(_ notification: Notification) {
        model = nil
        window = nil
    }
}

final class CommentsModel: ObservableObject {
    let fileURL: URL
    private let focusPage: Int?

    @Published private(set) var thumbnails: PageThumbnails?
    @Published private(set) var comments: [CommentRecord] = []
    @Published private(set) var undoLabel: String?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var search = ""
    /// Comments waiting for the user to confirm deletion (drives the dialog).
    @Published var pendingDelete: [CommentRecord]?
    @Published var selectionID: String? {
        didSet { if selectionID != oldValue { loadDraft() } }
    }

    @Published var draftText = ""
    @Published var draftColor: NoteColor = .yellow
    @Published var draftPlacement = CommentPlacement(page: 1, point: .zero)
    @Published var draftSpread: [Int] = [1]

    private var loadedModificationDate: Date?
    private var observer: NSObjectProtocol?

    init(fileURL: URL, focusPage: Int?) {
        self.fileURL = fileURL
        self.focusPage = focusPage
        reload()
        observer = NotificationCenter.default.addObserver(forName: .pdfMarkDocumentChanged, object: nil, queue: .main) { [weak self] note in
            guard let self, (note.object as? URL)?.standardizedFileURL == fileURL.standardizedFileURL, !self.isBusy else { return }
            self.reload()
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    var selected: CommentRecord? { comments.first { $0.id == selectionID } }

    var filtered: [CommentRecord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return comments }
        return comments.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) || "\($0.page)" == query
        }
    }

    var hasChanges: Bool {
        guard let s = selected else { return false }
        return draftText.trimmingCharacters(in: .whitespacesAndNewlines) != s.text
            || draftColor != s.color
            || !draftPlacement.isSamePosition(as: s.placement)
    }

    var canSave: Bool {
        hasChanges && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    // MARK: Loading

    func reload(selecting match: ((CommentRecord) -> Bool)? = nil) {
        undoLabel = UndoHistory.lastLabel(for: fileURL)
        guard let document = PDFDocument(url: fileURL) else {
            thumbnails = nil
            comments = []
            errorMessage = "Couldn't open \(fileURL.lastPathComponent)."
            return
        }
        loadedModificationDate = modificationDate()
        thumbnails = PageThumbnails(document: document)
        comments = CommentStore.comments(in: document)

        if let match, let found = comments.first(where: match) {
            selectionID = found.id
            loadDraft()
        } else if let selected {
            selectionID = selected.id
            loadDraft()
        } else {
            let first = focusPage.flatMap { page in comments.first { $0.page >= page } } ?? comments.first
            selectionID = first?.id
            loadDraft()
        }
    }

    func reloadIfChangedOnDisk() {
        if modificationDate() != loadedModificationDate { reload() }
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    func loadDraft() {
        guard let s = selected else { return }
        draftText = s.text
        draftColor = s.color
        draftPlacement = s.placement
        if !draftSpread.contains(s.page) || draftSpread.count < 2 {
            draftSpread = Spread.pair(containing: s.page, total: thumbnails?.pageCount ?? s.page)
        }
    }

    // MARK: Actions

    func saveDraft() {
        guard let record = selected, canSave else { return }
        let text = draftText, color = draftColor, placement = draftPlacement
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        perform(label: "Edit comment", page: placement.page, success: "Comment saved") {
            try CommentStore.update(record, in: self.fileURL, text: text, color: color, placement: placement)
        } selecting: { candidate in
            candidate.page == placement.page && candidate.text == trimmed
                && hypot(candidate.point.x - placement.point.x, candidate.point.y - placement.point.y) < 0.08
        }
    }

    /// Asks "delete?" first; nothing is removed until the user confirms.
    func requestDelete(_ records: [CommentRecord]) {
        guard !records.isEmpty, !isBusy else { return }
        pendingDelete = records
    }

    func requestDeleteSelected() {
        if let selected { requestDelete([selected]) }
    }

    func confirmPendingDelete() {
        guard let records = pendingDelete else { return }
        pendingDelete = nil
        delete(records)
    }

    func delete(_ records: [CommentRecord]) {
        guard !records.isEmpty else { return }
        let label = records.count == 1 ? "Delete comment" : "Delete \(records.count) comments"
        let success = records.count == 1 ? "Comment deleted" : "\(records.count) comments deleted"
        selectionID = nil
        perform(label: label, page: records.first?.page, success: success) {
            try CommentStore.delete(records, in: self.fileURL)
        }
    }

    func undo() {
        guard let label = undoLabel else { return }
        perform(label: nil, page: nil, success: "Undid “\(label)”") {
            try UndoHistory.undo(self.fileURL)
        }
    }

    func showInPreview(_ record: CommentRecord) {
        PreviewInspector.showPage(record.page, of: fileURL)
    }

    func copyAll() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var out = "Comments — \(fileURL.lastPathComponent)\n"
        for record in comments {
            var meta = ["Page \(record.page)"]
            if !record.author.isEmpty { meta.append(record.author) }
            if let date = record.date { meta.append(formatter.string(from: date)) }
            out += "\n" + meta.joined(separator: " · ") + "\n" + record.text + "\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
        Toast.success("Copied \(comments.count) comments")
    }

    private func perform(
        label: String?,
        page: Int?,
        success: String,
        change: @escaping () throws -> Void,
        selecting match: ((CommentRecord) -> Bool)? = nil
    ) {
        isBusy = true
        PreviewInspector.modify(fileURL, undoLabel: label, activatePreview: false, change: {
            try change()
            return page
        }) { [weak self] result in
            guard let self else { return }
            self.isBusy = false
            switch result {
            case .success:
                self.reload(selecting: match)
                Toast.success(success)
            case .failure(let error):
                self.reload()
                self.errorMessage = "\(error)"
            }
            NotificationCenter.default.post(name: .pdfMarkDocumentChanged, object: self.fileURL)
            // Reopening the PDF in Preview can pull focus; keep this window in front.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Views

private struct CommentsView: View {
    @ObservedObject var model: CommentsModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 310)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button { model.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .help(model.undoLabel.map { "Undo “\($0)”" } ?? "Nothing to undo")
                .disabled(model.undoLabel == nil || model.isBusy)

                Button { model.copyAll() } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .help("Copy all comments as text")
                .disabled(model.comments.isEmpty)

                Button { model.reload() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload comments from the file")
            }
        }
        .alert("Couldn't complete that", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(deleteTitle, isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } })) {
            Button("Delete", role: .destructive) { model.confirmPendingDelete() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { model.pendingDelete = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteTitle: String {
        let n = model.pendingDelete?.count ?? 0
        return n == 1 ? "Delete this comment?" : "Delete all \(n) comments?"
    }

    private var deleteMessage: String {
        guard let records = model.pendingDelete else { return "" }
        if records.count == 1, let r = records.first {
            let snippet = r.text.count > 80 ? String(r.text.prefix(80)) + "…" : r.text
            return "“\(snippet)” on page \(r.page) will be removed from the PDF. You can undo this afterwards."
        }
        return "This includes notes added in Preview. You can undo this afterwards."
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search comments", text: $model.search)
                    .textFieldStyle(.plain)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(12)

            if model.comments.isEmpty {
                emptyState(icon: "text.bubble", title: "No comments yet", message: "Choose “Add Comment…” from the PDFMark menu-bar icon while reading in Preview.")
            } else if model.filtered.isEmpty {
                emptyState(icon: "magnifyingglass", title: "No matches", message: "No comments contain “\(model.search)”.")
            } else {
                List(selection: $model.selectionID) {
                    ForEach(groupedByPage, id: \.page) { group in
                        Section {
                            ForEach(group.items) { record in
                                CommentRow(record: record)
                                    .tag(record.id)
                                    .contextMenu {
                                        Button("Show in Preview") { model.showInPreview(record) }
                                        Button("Copy Text") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(record.text, forType: .string)
                                        }
                                        Divider()
                                        Button("Delete…", role: .destructive) { model.requestDelete([record]) }
                                    }
                            }
                        } header: {
                            Text("Page \(group.page)")
                        }
                    }
                }
                .listStyle(.sidebar)
                .onDeleteCommand { model.requestDeleteSelected() }
            }

            Divider()
            HStack {
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Copy All as Text") { model.copyAll() }
                    Divider()
                    Button("Delete All Comments…", role: .destructive) { model.requestDelete(model.comments) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(model.comments.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.background)
    }

    private var countLabel: String {
        let n = model.comments.count
        let pages = Set(model.comments.map(\.page)).count
        return n == 0 ? "No comments" : "\(n) comment\(n == 1 ? "" : "s") on \(pages) page\(pages == 1 ? "" : "s")"
    }

    private var groupedByPage: [(page: Int, items: [CommentRecord])] {
        Dictionary(grouping: model.filtered, by: \.page)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.point.y < $1.point.y }) }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let record = model.selected, let thumbnails = model.thumbnails {
            CommentInspector(model: model, record: record, thumbnails: thumbnails)
                .id(record.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                Text(model.comments.isEmpty ? "Nothing to show" : "Select a comment")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CommentRow: View {
    let record: CommentRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NoteBadge(color: record.color, size: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.text.isEmpty ? "(empty note)" : record.text)
                    .font(.system(size: 13))
                    .lineLimit(3)
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var meta: String {
        var parts: [String] = []
        if !record.author.isEmpty { parts.append(record.author) }
        if let date = record.date {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.isEmpty ? "Page \(record.page)" : parts.joined(separator: " · ")
    }
}

private struct CommentInspector: View {
    @ObservedObject var model: CommentsModel
    let record: CommentRecord
    let thumbnails: PageThumbnails
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.draftPlacement.page == record.page
                         ? "Page \(record.page)"
                         : "Moving to page \(model.draftPlacement.page)")
                        .font(.system(size: 20, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.showInPreview(record)
                } label: {
                    Label("Show in Preview", systemImage: "arrow.up.forward.app")
                }
            }

            PagePickerCard(
                thumbnails: thumbnails,
                spread: $model.draftSpread,
                placement: $model.draftPlacement,
                color: model.draftColor,
                otherNotes: model.comments.filter { $0.id != record.id },
                height: 270
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Comment").font(.headline)
                    Spacer()
                    NoteColorPicker(selection: $model.draftColor)
                }
                CommentEditor(text: $model.draftText, focused: $textFocused, placeholder: "Comment text")
                    .frame(minHeight: 90, maxHeight: .infinity)
            }

            HStack {
                Button(role: .destructive) {
                    model.requestDelete([record])
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .help("Delete this comment (⌫ in the list) — can be undone")
                Spacer()
                if model.hasChanges {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Revert") { model.loadDraft() }
                    .disabled(!model.hasChanges)
                Button("Save Changes") { model.saveDraft() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSave)
            }
        }
        .padding(20)
        .disabled(model.isBusy)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !record.author.isEmpty { parts.append(record.author) }
        if let date = record.date { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}
