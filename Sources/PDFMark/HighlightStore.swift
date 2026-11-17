import AppKit
import PDFKit
import SwiftUI

enum HighlightError: Error, CustomStringConvertible {
    case noSelection
    case couldNotOpenDocument
    case textNotFound
    case writeFailed

    var description: String {
        switch self {
        case .noSelection: return "Select some text in Preview first"
        case .couldNotOpenDocument: return "Couldn't open the PDF file"
        case .textNotFound: return "Couldn't find the selected text in the PDF (is it a scanned page without real text?)"
        case .writeFailed: return "Couldn't save the PDF"
        }
    }
}

enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow, green, blue, pink, purple

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.90, blue: 0.25, alpha: 1)
        case .green: return NSColor(srgbRed: 0.55, green: 0.90, blue: 0.45, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.50, green: 0.78, blue: 1.00, alpha: 1)
        case .pink: return NSColor(srgbRed: 1.00, green: 0.56, blue: 0.75, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.78, green: 0.62, blue: 1.00, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

/// Text the user has selected in Preview. `start`/`end` are the first and last
/// selected characters, normalized to the page (0...1, origin top-left), when
/// Preview reports them — they pin down *which* occurrence was selected.
struct TextSelection {
    let fileURL: URL
    let page: Int
    let text: String
    var start: CGPoint?
    var end: CGPoint?
    /// Other pages to search if the text isn't found on `page`.
    var fallbackPages: [Int] = []
}

/// Writes standard PDF highlight annotations (`/Subtype /Highlight`) over the
/// selected text, one per line, so they look and behave exactly like
/// highlights made in Preview (and can be removed there, or undone in PDFMark).
enum HighlightStore {
    /// Highlights the selection and returns the page it landed on.
    @discardableResult
    static func add(_ selection: TextSelection, color: HighlightColor) throws -> Int {
        guard let document = PDFDocument(url: selection.fileURL) else { throw HighlightError.couldNotOpenDocument }

        var found: (PDFPage, PDFSelection, Int)?
        for pageNumber in [selection.page] + selection.fallbackPages.filter({ $0 != selection.page }) {
            guard let page = document.page(at: pageNumber - 1) else { continue }
            let usePoints = pageNumber == selection.page
            if let match = locate(selection, on: page, in: document, usePoints: usePoints) {
                found = (page, match, pageNumber)
                break
            }
        }
        guard let (page, match, pageNumber) = found else { throw HighlightError.textNotFound }

        let author = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        for line in match.selectionsByLine() {
            let b = line.bounds(for: page)
            guard b.width > 0.5, b.height > 0.5 else { continue }
            let annotation = PDFAnnotation(bounds: b, forType: .highlight, withProperties: nil)
            annotation.color = color.nsColor
            // Quad points are relative to the annotation's bounds origin.
            annotation.quadrilateralPoints = [
                NSValue(point: NSPoint(x: 0, y: b.height)),
                NSValue(point: NSPoint(x: b.width, y: b.height)),
                NSValue(point: NSPoint(x: 0, y: 0)),
                NSValue(point: NSPoint(x: b.width, y: 0)),
            ]
            annotation.userName = author
            annotation.modificationDate = Date()
            page.addAnnotation(annotation)
        }

        guard document.write(to: selection.fileURL) else { throw HighlightError.writeFailed }
        return pageNumber
    }

    /// Finds the selected text on the page. Preferred: the exact character span
    /// between the reported start/end points. Fallback: search the page's text,
    /// picking the occurrence closest to where the selection started.
    private static func locate(_ selection: TextSelection, on page: PDFPage, in document: PDFDocument, usePoints: Bool) -> PDFSelection? {
        let box = page.bounds(for: .cropBox)
        func pdfPoint(_ n: CGPoint) -> CGPoint {
            CGPoint(x: box.minX + n.x * box.width, y: box.maxY - n.y * box.height)
        }
        let anchor = usePoints ? selection.start.map(pdfPoint) : nil

        if usePoints, let start = selection.start, let end = selection.end,
           let candidate = page.selection(from: pdfPoint(start), to: pdfPoint(end)),
           similar(candidate.string ?? "", selection.text) {
            return candidate
        }

        guard let pageText = page.string as NSString? else { return nil }
        let ranges = occurrences(of: selection.text, in: pageText)
        let selections = ranges.compactMap { range -> PDFSelection? in
            guard range.length > 0 else { return nil }
            return document.selection(from: page, atCharacterIndex: range.location, to: page, atCharacterIndex: NSMaxRange(range) - 1)
        }
        guard let anchor else { return selections.first }
        return selections.min { distance($0.bounds(for: page), anchor) < distance($1.bounds(for: page), anchor) }
    }

    /// Ranges in the page text matching the selection. Tries the exact text,
    /// then a whitespace-insensitive match, then (for multi-line selections) the
    /// span from the first line to the last line.
    private static func occurrences(of text: String, in pageText: NSString) -> [NSRange] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        func all(_ needle: String, options: NSString.CompareOptions = [.caseInsensitive]) -> [NSRange] {
            var result: [NSRange] = []
            var search = NSRange(location: 0, length: pageText.length)
            while search.length > 0 {
                let r = pageText.range(of: needle, options: options, range: search)
                guard r.location != NSNotFound else { break }
                result.append(r)
                search = NSRange(location: NSMaxRange(r), length: pageText.length - NSMaxRange(r))
            }
            return result
        }

        var ranges = all(trimmed)
        if ranges.isEmpty {
            let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                .map(NSRegularExpression.escapedPattern(for:))
            let pattern = words.joined(separator: "[\\s\\-\u{00AD}]*")
            ranges = all(pattern, options: [.caseInsensitive, .regularExpression])
        }
        if ranges.isEmpty {
            let lines = trimmed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if lines.count > 1, let firstLine = lines.first, let lastLine = lines.last {
                for first in all(firstLine) {
                    let rest = NSRange(location: NSMaxRange(first), length: pageText.length - NSMaxRange(first))
                    let last = pageText.range(of: lastLine, options: .caseInsensitive, range: rest)
                    if last.location != NSNotFound {
                        ranges.append(NSRange(location: first.location, length: NSMaxRange(last) - first.location))
                    }
                }
            }
        }
        return ranges
    }

    private static func similar(_ a: String, _ b: String) -> Bool {
        func normalize(_ s: String) -> String {
            s.lowercased().unicodeScalars
                .filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "-" && $0 != "\u{00AD}" }
                .map(String.init).joined()
        }
        let x = normalize(a), y = normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        let shorter = min(x.count, y.count), longer = max(x.count, y.count)
        return (x.contains(y) || y.contains(x)) && Double(shorter) / Double(longer) > 0.85
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }
}
