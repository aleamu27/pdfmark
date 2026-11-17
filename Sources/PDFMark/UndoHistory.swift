import CryptoKit
import Foundation

enum UndoHistoryError: Error, CustomStringConvertible {
    case nothingToUndo

    var description: String { "There's nothing to undo for this document" }
}

/// Per-document undo for PDFMark's own changes. Before every change a copy of
/// the PDF is stored in Application Support (newest 20 per document); undo
/// restores the most recent copy. Because PDFMark rewrites the file on disk, this
/// is the safety net that makes every bookmark/comment edit reversible.
enum UndoHistory {
    private static let maxEntries = 20

    private struct Entry {
        let pdf: URL
        var labelFile: URL { pdf.deletingPathExtension().appendingPathExtension("txt") }
        var label: String { (try? String(contentsOf: labelFile, encoding: .utf8)) ?? "Change" }
    }

    private static func directory(for url: URL) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PDFMark/Undo", isDirectory: true)
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent(String(digest.prefix(24)), isDirectory: true)
    }

    private static func entries(for url: URL) -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(for: url), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(Entry.init)
    }

    private static func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.pdf)
        try? FileManager.default.removeItem(at: entry.labelFile)
    }

    /// Stores the file's current state, to be restored by `undo`.
    static func snapshot(_ url: URL, label: String) throws {
        let dir = directory(for: url)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = String(format: "%015.0f", Date().timeIntervalSince1970 * 1000)
        let entry = Entry(pdf: dir.appendingPathComponent("\(stamp).pdf"))
        try FileManager.default.copyItem(at: url, to: entry.pdf)
        try label.write(to: entry.labelFile, atomically: true, encoding: .utf8)
        entries(for: url).dropLast(maxEntries).forEach(remove)
    }

    /// Drops the newest snapshot (used when the change it guarded failed).
    static func discardLatest(_ url: URL) {
        entries(for: url).last.map(remove)
    }

    static func lastLabel(for url: URL) -> String? {
        entries(for: url).last?.label
    }

    /// Restores the newest snapshot over the file and returns its label.
    @discardableResult
    static func undo(_ url: URL) throws -> String {
        guard let entry = entries(for: url).last else { throw UndoHistoryError.nothingToUndo }
        let label = entry.label
        try Data(contentsOf: entry.pdf).write(to: url, options: .atomic)
        remove(entry)
        return label
    }
}
