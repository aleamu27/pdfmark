import PDFKit
import Foundation

let path = "/Users/alexanderamundsen/Downloads/Eksamen REA3058 Matematikk R2 V26.pdf"
guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { exit(1) }
guard let page = doc.page(at: 2) else { exit(1) }
for a in page.annotations {
    print("annotation type=\(a.type ?? "?") userName=\(a.userName ?? "nil") bounds=\(a.bounds) contents=\(a.contents ?? "nil")")
}
