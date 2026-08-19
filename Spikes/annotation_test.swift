import PDFKit
import Foundation
import AppKit

let doc = PDFDocument()
for i in 0..<3 {
    let page = PDFPage()
    doc.insert(page, at: i)
}
guard let page = doc.page(at: 1) else { exit(1) }
let mediaBox = page.bounds(for: .mediaBox)
let size: CGFloat = 22
let margin: CGFloat = 14
let bounds = CGRect(x: mediaBox.width - size - margin, y: mediaBox.height - size - margin, width: size, height: size)

let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
annotation.iconType = .note
annotation.contents = "Bokmerke — side 2"
annotation.color = NSColor.systemYellow
annotation.userName = "PDFMark"
page.addAnnotation(annotation)

let outPath = "/Users/alexanderamundsen/Documents/pdfbuddy/Spikes/annotation_test.pdf"
let ok = doc.write(to: URL(fileURLWithPath: outPath))
print("write ok: \(ok) -> \(outPath)")
