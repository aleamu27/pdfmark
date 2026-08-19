import PDFKit
import Foundation
import AppKit

final class RibbonAnnotation: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let b = self.bounds
        let w = b.width
        let h = b.height
        let notchHeight = h * 0.28

        let path = CGMutablePath()
        path.move(to: CGPoint(x: b.minX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.minY))
        path.addLine(to: CGPoint(x: b.minX + w / 2, y: b.minY + notchHeight))
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

let doc = PDFDocument()
for i in 0..<3 {
    let page = PDFPage()
    doc.insert(page, at: i)
}
guard let page = doc.page(at: 1) else { exit(1) }
let mediaBox = page.bounds(for: .mediaBox)

let ribbonW: CGFloat = 22
let ribbonH: CGFloat = 46
let rightMargin: CGFloat = 30
let bounds = CGRect(x: mediaBox.width - rightMargin - ribbonW, y: mediaBox.height - ribbonH, width: ribbonW, height: ribbonH)

let annotation = RibbonAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
annotation.contents = "Bokmerke — side 2"
annotation.userName = "PDFMark"
page.addAnnotation(annotation)

let outPath = "/Users/alexanderamundsen/Documents/pdfbuddy/Spikes/ribbon_test.pdf"
let ok = doc.write(to: URL(fileURLWithPath: outPath))
print("write ok: \(ok) -> \(outPath)")
