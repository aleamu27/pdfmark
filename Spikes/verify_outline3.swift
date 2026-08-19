import PDFKit
import Foundation

let path = "/Users/alexanderamundsen/Downloads/Eksamen REA3058 Matematikk R2 V26.pdf"
guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { exit(1) }
guard let root = doc.outlineRoot else { print("no root"); exit(1) }
for i in 0..<min(4, root.numberOfChildren) {
    if let c = root.child(at: i) {
        print("[\(i)] label=\(c.label ?? "?")")
        print("   destination=\(String(describing: c.destination))")
        print("   destination.page=\(String(describing: c.destination?.page))")
        print("   action=\(String(describing: c.action))")
        if let a = c.action {
            print("   action type=\(type(of: a))")
        }
    }
}
