import PDFKit
import Foundation

let path = "/Users/alexanderamundsen/Documents/pdfbuddy/Spikes/reload_test_copy.pdf"
let url = URL(fileURLWithPath: path)
guard let doc = PDFDocument(url: url) else {
    print("failed to open")
    exit(1)
}
guard let page = doc.page(at: 4) else { // 0-indexed -> page 5
    print("no page 5")
    exit(1)
}
let dest = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height))
let outlineItem = PDFOutline()
outlineItem.label = "TEST-BOKMERKE (spike)"
outlineItem.destination = dest

let root = doc.outlineRoot ?? PDFOutline()
if doc.outlineRoot == nil {
    doc.outlineRoot = root
}
root.insertChild(outlineItem, at: root.numberOfChildren)

let ok = doc.write(to: url)
print("write success: \(ok)")
