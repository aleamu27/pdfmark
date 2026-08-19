import PDFKit
import Foundation

let path = "/Users/alexanderamundsen/Downloads/Eksamen REA3058 Matematikk R2 V26.pdf"
guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
    print("failed to open"); exit(1)
}
if let root = doc.outlineRoot {
    print("outlineRoot children: \(root.numberOfChildren)")
    for i in 0..<root.numberOfChildren {
        if let child = root.child(at: i) {
            print("  [\(i)] label=\(child.label ?? "nil") dest page index=\(doc.index(for: child.destination?.page ?? PDFPage()))")
        }
    }
} else {
    print("NO outlineRoot at all")
}
