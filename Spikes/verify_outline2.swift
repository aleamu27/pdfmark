import PDFKit
import Foundation

let path = "/Users/alexanderamundsen/Downloads/Eksamen REA3058 Matematikk R2 V26.pdf"
guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { exit(1) }
guard let root = doc.outlineRoot else { print("no root"); exit(1) }
func pageIndex(_ o: PDFOutline) -> Int? {
    if let p = o.destination?.page { return doc.index(for: p) }
    if let action = o.action as? PDFActionGoTo, let p = action.destination.page { return doc.index(for: p) }
    return nil
}
for i in 0..<min(6, root.numberOfChildren) {
    if let c = root.child(at: i) {
        print("[\(i)] \(c.label ?? "?") -> pageIndex=\(pageIndex(c).map(String.init) ?? "nil")")
    }
}
