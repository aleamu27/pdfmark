import AppKit
import PDFKit
import SwiftUI

enum CommentError: Error, CustomStringConvertible {
    case couldNotOpenDocument
    case pageOutOfRange
    case emptyComment
    case notFound
    case writeFailed

    var description: String {
        switch self {
        case .couldNotOpenDocument: return "Couldn't open the PDF file"
        case .pageOutOfRange: return "That page doesn't exist in the document"
        case .emptyComment: return "The comment is empty"
        case .notFound: return "That comment has changed or was removed — refresh and try again"
        case .writeFailed: return "Couldn't save the PDF"
        }
    }
}

/// Where a comment goes: a 1-indexed page and the note icon's center as a
/// fraction of the page (origin top-left, 0...1 on both axes).
struct CommentPlacement: Equatable {
    var page: Int
    var point: CGPoint

    func isSamePosition(as other: CommentPlacement) -> Bool {
        page == other.page && hypot(point.x - other.point.x, point.y - other.point.y) < 0.001
    }
}

enum NoteColor: String, CaseIterable, Identifiable {
    case yellow, orange, red, green, blue, purple

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.82, blue: 0.20, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.20, alpha: 1)
        case .red: return NSColor(srgbRed: 0.95, green: 0.33, blue: 0.33, alpha: 1)
        case .green: return NSColor(srgbRed: 0.35, green: 0.78, blue: 0.40, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.30, green: 0.58, blue: 1.00, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.68, green: 0.45, blue: 0.95, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Maps any note color (e.g. one picked in Preview) to the closest swatch.
    static func nearest(to color: NSColor?) -> NoteColor {
        guard let c = color?.usingColorSpace(.sRGB) else { return .yellow }
        func distance(_ n: NoteColor) -> CGFloat {
            let o = n.nsColor
            return pow(o.redComponent - c.redComponent, 2) + pow(o.greenComponent - c.greenComponent, 2) + pow(o.blueComponent - c.blueComponent, 2)
        }
        return allCases.min { distance($0) < distance($1) } ?? .yellow
    }
}

/// A sticky note whose icon is PDFMark's own badge (`MarkerArt.drawNote`)
/// instead of the viewer's dated default. PDFKit writes the drawing into the
/// note's appearance stream on save; Preview and other viewers render that.
final class NoteAnnotation: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        MarkerArt.drawNote(in: bounds, color: color, context: context)
    }
}

/// A note as listed in the comments window. `index` is its position among the
/// note annotations on its page; together with `bounds` it relocates the exact
/// annotation when the file is reopened for an edit.
struct CommentRecord: Identifiable, Equatable {
    let page: Int
    let index: Int
    let bounds: CGRect
    let text: String
    let author: String
    let date: Date?
    let color: NoteColor
    let point: CGPoint

    var id: String { "\(page)-\(index)-\(Int(bounds.minX))-\(Int(bounds.minY))" }
    var placement: CommentPlacement { CommentPlacement(page: page, point: point) }
}

/// Reads and writes comments as standard PDF "Text" annotations (sticky notes):
/// a small clickable note icon that sits *on top of* the page without altering
/// its content, and opens a popup with the text when clicked — in Preview and
/// every other PDF viewer. Notes created in Preview itself are included too.
enum CommentStore {
    static let iconSize: CGFloat = 24  // PDFKit normalizes note icons to 24×24
    private static let rightMargin: CGFloat = 8
    /// Keep clear of the bookmark ribbon hanging from the top edge.
    private static let topClearance: CGFloat = 56
    private static let stackSpacing: CGFloat = 4

    static var currentAuthor: String {
        NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
    }

    // MARK: Reading

    static func comments(in document: PDFDocument) -> [CommentRecord] {
        var result: [CommentRecord] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let box = page.bounds(for: .cropBox)
            for (index, note) in notes(on: page).enumerated() {
                let point = CGPoint(
                    x: (note.bounds.midX - box.minX) / box.width,
                    y: (box.maxY - note.bounds.midY) / box.height
                )
                result.append(CommentRecord(
                    page: pageIndex + 1,
                    index: index,
                    bounds: note.bounds,
                    text: note.contents ?? "",
                    author: note.userName ?? "",
                    date: note.modificationDate,
                    color: NoteColor.nearest(to: note.color),
                    point: point
                ))
            }
        }
        return result
    }

    /// The default spot for a new note, as a normalized point: the page's right
    /// margin at the given height (0 = top, 1 = bottom), below the bookmark ribbon.
    static func defaultPoint(on page: PDFPage, verticalFraction: CGFloat?) -> CGPoint {
        let box = page.bounds(for: .cropBox)
        let x = 1 - (rightMargin + iconSize / 2) / box.width
        let minY = (topClearance + iconSize / 2) / box.height
        let maxY = 1 - (rightMargin + iconSize / 2) / box.height
        return CGPoint(x: x, y: min(max(verticalFraction ?? 0, minY), maxY))
    }

    // MARK: Writing

    static func add(to url: URL, at placement: CommentPlacement, text: String, color: NoteColor) throws {
        let text = try validated(text)
        let document = try open(url)
        let page = try page(placement.page, in: document)
        insertNote(on: page, at: placement.point, text: text, color: color, author: currentAuthor)
        try save(document, to: url)
    }

    /// Changes a note's text/color in place, or recreates it if it was moved
    /// (possibly to another page — a PDF note always belongs to exactly one page).
    static func update(_ record: CommentRecord, in url: URL, text: String, color: NoteColor, placement: CommentPlacement) throws {
        let text = try validated(text)
        let document = try open(url)
        let page = try page(record.page, in: document)
        guard let note = locate(record, on: page) else { throw CommentError.notFound }

        if placement.isSamePosition(as: record.placement) && color == record.color {
            note.contents = text
            note.modificationDate = Date()
            note.popup?.contents = text
        } else {
            // Recreated so the badge is redrawn in its new color/position (an
            // existing appearance stream isn't regenerated by a color change).
            let author = note.userName ?? currentAuthor
            let bounds = note.bounds
            remove(note, from: page)
            let target = try self.page(placement.page, in: document)
            if placement.isSamePosition(as: record.placement) {
                insertNote(on: target, bounds: bounds, text: text, color: color, author: author)
            } else {
                insertNote(on: target, at: placement.point, text: text, color: color, author: author)
            }
        }
        try save(document, to: url)
    }

    static func delete(_ records: [CommentRecord], in url: URL) throws {
        let document = try open(url)
        // Locate everything first: removing shifts the per-page indices.
        var targets: [(PDFPage, PDFAnnotation)] = []
        for record in records {
            let page = try page(record.page, in: document)
            if let note = locate(record, on: page) { targets.append((page, note)) }
        }
        guard !targets.isEmpty else { throw CommentError.notFound }
        for (page, note) in targets { remove(note, from: page) }
        try save(document, to: url)
    }

    // MARK: Helpers

    private static func notes(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { $0.type == "Text" }
    }

    private static func validated(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommentError.emptyComment }
        return trimmed
    }

    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw CommentError.couldNotOpenDocument }
        return document
    }

    private static func page(_ page1Indexed: Int, in document: PDFDocument) throws -> PDFPage {
        guard let page = document.page(at: page1Indexed - 1) else { throw CommentError.pageOutOfRange }
        return page
    }

    private static func save(_ document: PDFDocument, to url: URL) throws {
        guard document.write(to: url) else { throw CommentError.writeFailed }
    }

    private static func locate(_ record: CommentRecord, on page: PDFPage) -> PDFAnnotation? {
        let notes = notes(on: page)
        func sameSpot(_ a: PDFAnnotation) -> Bool {
            abs(a.bounds.minX - record.bounds.minX) < 0.5 && abs(a.bounds.minY - record.bounds.minY) < 0.5
        }
        if record.index < notes.count, sameSpot(notes[record.index]) { return notes[record.index] }
        return notes.first { sameSpot($0) && ($0.contents ?? "") == record.text } ?? notes.first(where: sameSpot)
    }

    /// Removes a note and its popup. PDFKit hands back a different object for
    /// `note.popup` than the one in `page.annotations`, so popups are matched by
    /// position; any popup no longer referenced by an annotation on the page
    /// (e.g. left behind by an earlier delete) is cleaned up too.
    private static func remove(_ note: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(note)
        let referenced = page.annotations
            .filter { $0.type != "Popup" }
            .compactMap { $0.popup?.bounds }
        for popup in page.annotations where popup.type == "Popup" && !referenced.contains(popup.bounds) {
            page.removeAnnotation(popup)
        }
    }

    private static func insertNote(on page: PDFPage, at point: CGPoint, text: String, color: NoteColor, author: String) {
        insertNote(on: page, bounds: noteBounds(on: page, normalizedCenter: point), text: text, color: color, author: author)
    }

    private static func insertNote(on page: PDFPage, bounds: CGRect, text: String, color: NoteColor, author: String) {
        let note = NoteAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        note.contents = text
        note.iconType = .comment
        note.color = color.nsColor
        note.userName = author
        note.modificationDate = Date()
        page.addAnnotation(note)
    }

    /// Converts the normalized point to page coordinates (PDF origin is bottom-
    /// left), keeps the icon fully on the page, and nudges it past any existing
    /// note it would land on so icons never hide each other.
    private static func noteBounds(on page: PDFPage, normalizedCenter p: CGPoint) -> CGRect {
        let box = page.bounds(for: .cropBox)
        let minX = box.minX, maxX = box.maxX - iconSize
        let minY = box.minY, maxY = box.maxY - iconSize
        let x = min(max(box.minX + p.x * box.width - iconSize / 2, minX), maxX)
        let y = min(max(box.maxY - p.y * box.height - iconSize / 2, minY), maxY)

        let occupied = notes(on: page).map(\.bounds)
        let candidate = CGRect(x: x, y: y, width: iconSize, height: iconSize)
        for direction: CGFloat in [-1, 1] {
            var probe = candidate
            while occupied.contains(where: { $0.insetBy(dx: -stackSpacing / 2, dy: -stackSpacing / 2).intersects(probe) }) {
                probe.origin.y += direction * (iconSize + stackSpacing)
            }
            if probe.minY >= minY && probe.minY <= maxY { return probe }
        }
        return candidate
    }
}
