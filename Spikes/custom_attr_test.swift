import PDFKit
import Foundation

let path = "/Users/alexanderamundsen/Documents/pdfbuddy/Spikes/attr_test.pdf"
// make a tiny throwaway pdf to test custom Info dict key round-trip
let pdfDoc = PDFDocument()
let page = PDFPage()
pdfDoc.insert(page, at: 0)

var attrs = pdfDoc.documentAttributes ?? [:]
let customKey = PDFDocumentAttribute(rawValue: "PDFMarkTool")
attrs[customKey] = "true"
pdfDoc.documentAttributes = attrs

let ok = pdfDoc.write(to: URL(fileURLWithPath: path))
print("write ok: \(ok)")

guard let reopened = PDFDocument(url: URL(fileURLWithPath: path)) else {
    print("failed reopen"); exit(1)
}
let reAttrs = reopened.documentAttributes ?? [:]
print("attrs after reopen: \(reAttrs)")
if let v = reAttrs[customKey] {
    print("CUSTOM KEY SURVIVED: \(v)")
} else {
    print("custom key did NOT survive")
}
