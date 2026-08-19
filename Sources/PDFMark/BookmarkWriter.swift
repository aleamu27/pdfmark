import AppKit
import Foundation
import PDFKit

enum BookmarkWriterError: Error, CustomStringConvertible {
    case couldNotOpenDocument
    case pageOutOfRange
    case writeFailed

    var description: String {
        switch self {
        case .couldNotOpenDocument: return "Couldn't open the PDF file"
        case .pageOutOfRange: return "That page number doesn't exist in the document"
        case .writeFailed: return "Couldn't save the bookmark"
        }
    }
}

/// Draws a small red bookmark-ribbon shape hanging from the top edge of the page.
/// PDFKit bakes the result of `draw(with:in:)` into the annotation's appearance
/// stream when the document is written to disk, so this renders identically in
/// any PDF viewer afterwards (verified against Preview.app), not just inside a
/// PDFKit-backed view in this app.
private final class RibbonAnnotation: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let b = bounds
        let notchHeight = b.height * 0.28

        let path = CGMutablePath()
        path.move(to: CGPoint(x: b.minX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.minY))
        path.addLine(to: CGPoint(x: b.minX + b.width / 2, y: b.minY + notchHeight))
        path.addLine(to: CGPoint(x: b.minX, y: b.minY))
        path.closeSubpath()

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.addPath(path)
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(NSColor.red.blended(withFraction: 0.3, of: .black)!.cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
        context.restoreGState()
    }
}

enum BookmarkWriter {
    /// Zero-width marker appended to outline labels created by this app. Invisible in
    /// Preview's table of contents, but lets future code (e.g. an "undo") find and
    /// remove exactly the entries PDFMark added without touching the document's own
    /// pre-existing outline structure.
    private static let marker = "\u{200B}"
    private static let annotationAuthor = "PDFMark"
    private static let ribbonWidth: CGFloat = 22
    private static let ribbonHeight: CGFloat = 46
    private static let ribbonRightMargin: CGFloat = 30

    /// Adds a bookmark (outline entry + visible corner ribbon) for the given
    /// 1-indexed page number, and writes the PDF back to the same file. PDFMark
    /// only ever keeps one active bookmark per document — any previous PDFMark
    /// entry/ribbon is removed first (the document's own pre-existing outline is
    /// left untouched).
    static func addBookmark(to url: URL, page1Indexed: Int) throws {
        guard let document = PDFDocument(url: url) else {
            throw BookmarkWriterError.couldNotOpenDocument
        }
        let pageIndex = page1Indexed - 1
        guard pageIndex >= 0, let page = document.page(at: pageIndex) else {
            throw BookmarkWriterError.pageOutOfRange
        }

        removeExistingBookmark(from: document)
        addOutlineEntry(to: document, page: page, pageIndex: pageIndex, page1Indexed: page1Indexed)
        addRibbon(to: page, page1Indexed: page1Indexed)

        guard document.write(to: url) else {
            throw BookmarkWriterError.writeFailed
        }
    }

    private static func removeExistingBookmark(from document: PDFDocument) {
        if let root = document.outlineRoot {
            let newRoot = PDFOutline()
            var kept = 0
            for i in 0..<root.numberOfChildren {
                guard let child = root.child(at: i) else { continue }
                if let label = child.label, label.contains(marker) { continue }
                newRoot.insertChild(child, at: kept)
                kept += 1
            }
            document.outlineRoot = newRoot
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.userName == annotationAuthor {
                page.removeAnnotation(annotation)
            }
        }
    }

    private static func addOutlineEntry(to document: PDFDocument, page: PDFPage, pageIndex: Int, page1Indexed: Int) {
        let root = document.outlineRoot ?? PDFOutline()
        if document.outlineRoot == nil {
            document.outlineRoot = root
        }

        let destination = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height))
        let newItem = PDFOutline()
        newItem.label = "Bookmark — page \(page1Indexed)\(marker)"
        newItem.destination = destination

        // Only compare against entries PDFMark itself created (identified via the
        // marker); we resolve their page reliably since we set their destination
        // ourselves. Sorting against the document's own pre-existing outline is not
        // attempted since many real-world PDFs have top-level entries with no
        // directly resolvable page destination (section headers, named destinations
        // PDFKit doesn't resolve, etc.) — sorting against those risks scrambling a
        // TOC structure the author organized on purpose. New PDFMark entries are
        // therefore grouped together after the document's existing entries.
        var insertionIndex = root.numberOfChildren
        for i in 0..<root.numberOfChildren {
            guard let child = root.child(at: i), let label = child.label, label.contains(marker) else { continue }
            if let childPageIndex = child.destination?.page.flatMap({ document.index(for: $0) }),
               childPageIndex > pageIndex {
                insertionIndex = i
                break
            }
            insertionIndex = i + 1
        }

        root.insertChild(newItem, at: insertionIndex)
    }

    private static func addRibbon(to page: PDFPage, page1Indexed: Int) {
        let mediaBox = page.bounds(for: .mediaBox)
        let bounds = CGRect(
            x: mediaBox.width - ribbonRightMargin - ribbonWidth,
            y: mediaBox.height - ribbonHeight,
            width: ribbonWidth,
            height: ribbonHeight
        )
        let annotation = RibbonAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
        annotation.contents = "Bookmark — page \(page1Indexed)"
        annotation.userName = annotationAuthor
        page.addAnnotation(annotation)
    }
}
