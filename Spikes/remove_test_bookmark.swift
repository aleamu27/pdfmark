import PDFKit
import Foundation

let path = "/Users/alexanderamundsen/Downloads/Eksamen REA3058 Matematikk R2 V26.pdf"
let url = URL(fileURLWithPath: path)
guard let doc = PDFDocument(url: url), let root = doc.outlineRoot else {
    print("failed to open or no outline"); exit(1)
}
let marker = "\u{200B}"
let newRoot = PDFOutline()
var removedCount = 0
var kept = 0
for i in 0..<root.numberOfChildren {
    if let child = root.child(at: i) {
        if let label = child.label, label.contains(marker) {
            removedCount += 1
            continue
        }
        newRoot.insertChild(child, at: kept)
        kept += 1
    }
}
doc.outlineRoot = newRoot
print("removed \(removedCount) test entries, kept \(kept)")
let ok = doc.write(to: url)
print("write success: \(ok)")
