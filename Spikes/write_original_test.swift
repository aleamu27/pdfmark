import PDFKit
import Foundation

let path = "/Users/alexanderamundsen/Downloads/Eksamen REA3058 Matematikk R2 V26.pdf"
let url = URL(fileURLWithPath: path)
guard let doc = PDFDocument(url: url) else {
    print("failed to open"); exit(1)
}
guard let page = doc.page(at: 3) else { // 0-indexed -> page 4
    print("no page 4"); exit(1)
}
let marker = "\u{200B}" // zero-width space: invisible code-level tag for PDFMark-created entries
let dest = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height))
let outlineItem = PDFOutline()
outlineItem.label = "Bokmerke — side 4\(marker)"
outlineItem.destination = dest

let root = doc.outlineRoot ?? PDFOutline()
if doc.outlineRoot == nil { doc.outlineRoot = root }
root.insertChild(outlineItem, at: root.numberOfChildren)

let ok = doc.write(to: url)
print("write success: \(ok)")
