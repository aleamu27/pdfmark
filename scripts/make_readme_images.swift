// Renders the illustrations used in README.md into docs/images/.
// Run via ./scripts/make_readme_images.sh (compiled together with MarkerArt.swift,
// so the ribbon and note badges are exactly what the app draws onto PDFs).
import AppKit
import CoreText
import PDFKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let indigoTop = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.98, alpha: 1)
let indigoBottom = NSColor(srgbRed: 0.20, green: 0.22, blue: 0.62, alpha: 1)
let accent = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
let noteColors: [(String, NSColor)] = [
    ("Yellow", NSColor(srgbRed: 1.00, green: 0.82, blue: 0.20, alpha: 1)),
    ("Orange", NSColor(srgbRed: 1.00, green: 0.58, blue: 0.20, alpha: 1)),
    ("Red", NSColor(srgbRed: 0.95, green: 0.33, blue: 0.33, alpha: 1)),
    ("Green", NSColor(srgbRed: 0.35, green: 0.78, blue: 0.40, alpha: 1)),
    ("Blue", NSColor(srgbRed: 0.30, green: 0.58, blue: 1.00, alpha: 1)),
    ("Purple", NSColor(srgbRed: 0.68, green: 0.45, blue: 0.95, alpha: 1)),
]

// MARK: - Helpers

/// Draws into a flipped (y-down) canvas at 2x and writes a PNG.
func render(_ name: String, _ size: CGSize, _ draw: (CGContext) -> Void) {
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name)")
}

/// Runs `body` in a y-up coordinate space whose origin is `rect`'s bottom-left
/// (for MarkerArt and PDF pages, which are drawn y-up).
func upright(_ ctx: CGContext, _ rect: CGRect, _ body: (CGRect) -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    body(CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, align: NSTextAlignment = .left, width: CGFloat = 1000) {
    let style = NSMutableParagraphStyle(); style.alignment = align
    let str = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    let x = align == .center ? p.x - width / 2 : (align == .right ? p.x - width : p.x)
    str.draw(in: CGRect(x: x, y: p.y, width: width, height: size * 3))
}

func symbol(_ name: String, in rect: CGRect, color: NSColor, weight: NSFont.Weight = .regular) {
    let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: weight).applying(.init(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    let s = img.size
    let r = CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height)
    img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

func roundedRect(_ ctx: CGContext, _ r: CGRect, radius: CGFloat, fill: NSColor, shadow: (CGFloat, CGFloat, CGFloat)? = nil, stroke: NSColor? = nil) {
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    if let (y, blur, a) = shadow { ctx.setShadow(offset: CGSize(width: 0, height: y), blur: blur, color: NSColor.black.withAlphaComponent(a).cgColor) }
    ctx.addPath(path); ctx.setFillColor(fill.cgColor); ctx.fillPath()
    ctx.restoreGState()
    if let stroke { ctx.addPath(path); ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(1); ctx.strokePath() }
}

func gradientBackground(_ ctx: CGContext, _ r: CGRect, radius: CGFloat) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [indigoTop.cgColor, indigoBottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX * 0.6, y: r.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// MARK: - Sample document

final class NoteArt: PDFAnnotation { override func draw(with box: PDFDisplayBox, in c: CGContext) { MarkerArt.drawNote(in: bounds, color: color, context: c) } }
final class RibbonArt: PDFAnnotation { override func draw(with box: PDFDisplayBox, in c: CGContext) { MarkerArt.drawRibbon(in: bounds, context: c) } }

func makeSampleDocument() -> PDFDocument {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    let chapters = [
        ("The Quiet Craft of Reading", "Reading well is less about speed than about attention. A page rewards the reader who returns to it, who marks it, who argues with it in the margin."),
        ("Marking What Matters", "A bookmark is a promise to come back. The best ones are placed without breaking the flow of reading — a single gesture, and the thought is safe."),
    ]
    let body = String(repeating: "Most of what we read slips away within days unless we do something with it. Underlining is cheap; a deliberate note is not. The effort of choosing a place and writing a sentence is exactly what makes the idea stick. Good tools make that effort small without making it thoughtless. ", count: 3)
    func para(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSAttributedString {
        let p = NSMutableParagraphStyle(); p.lineSpacing = 5; p.paragraphSpacing = 12
        return NSAttributedString(string: s + "\n", attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p])
    }
    for (i, ch) in chapters.enumerated() {
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(box)
        let t = NSMutableAttributedString()
        t.append(para("CHAPTER \(i + 1)", 10, .semibold, indigoTop))
        t.append(para(ch.0, 26, .bold, .black))
        t.append(para(ch.1, 13, .medium, .darkGray))
        t.append(para(body, 11, .regular, NSColor(white: 0.15, alpha: 1)))
        t.append(para(body, 11, .regular, NSColor(white: 0.15, alpha: 1)))
        let fs = CTFramesetterCreateWithAttributedString(t)
        CTFrameDraw(CTFramesetterCreateFrame(fs, CFRange(), CGPath(rect: CGRect(x: 64, y: 70, width: 467, height: 700), transform: nil), nil), ctx)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    let doc = PDFDocument(data: data as Data)!
    doc.page(at: 1)!.addAnnotation(RibbonArt(bounds: CGRect(x: 541, y: 798, width: 24, height: 44), forType: .stamp, withProperties: nil))
    for (page, x, y, color) in [(0, 545.0, 600.0, 4), (1, 545.0, 640.0, 0), (1, 545.0, 430.0, 3)] {
        let n = NoteArt(bounds: CGRect(x: x, y: y, width: 24, height: 24), forType: .text, withProperties: nil)
        n.color = noteColors[color].1
        doc.page(at: page)!.addAnnotation(n)
    }
    return doc
}

func drawPage(_ ctx: CGContext, _ page: PDFPage, in rect: CGRect) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 10, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.setFillColor(NSColor.white.cgColor); ctx.fill(rect)
    ctx.restoreGState()
    upright(ctx, rect) { r in
        let media = page.bounds(for: .mediaBox)
        ctx.scaleBy(x: r.width / media.width, y: r.height / media.height)
        page.draw(with: .mediaBox, to: ctx)
    }
}

// MARK: - Hero

func drawMenu(_ ctx: CGContext, at origin: CGPoint) {
    let width: CGFloat = 300
    let rows: [(String?, String, String?, Bool)] = [
        ("bookmark", "Bookmark This Page", "⌘B", false),
        ("text.bubble", "Add Comment…", "⌘K", true),
        ("list.bullet.rectangle", "Show All Comments (3)…", "⌘L", false),
        (nil, "-", nil, false),
        ("arrow.turn.down.right", "Go to Bookmark — Page 2", nil, false),
        ("bookmark.slash", "Remove Bookmark", nil, false),
        (nil, "-", nil, false),
        ("arrow.uturn.backward", "Undo “Add comment”", "⌘Z", false),
        (nil, "-", nil, false),
        ("power", "Open at Login", nil, false),
        ("questionmark.circle", "Show Introduction…", nil, false),
        (nil, "Quit PDFMark", "⌘Q", false),
    ]
    let height: CGFloat = 62 + rows.reduce(0) { $0 + ($1.1 == "-" ? 11 : 24) } + 8
    let menuRect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    roundedRect(ctx, menuRect, radius: 11, fill: NSColor(white: 0.97, alpha: 0.98), shadow: (12, 30, 0.35), stroke: NSColor(white: 0, alpha: 0.08))

    var y = origin.y + 10
    symbol("doc.richtext", in: CGRect(x: origin.x + 14, y: y + 6, width: 20, height: 18), color: .gray)
    text("Deep Reading.pdf", at: CGPoint(x: origin.x + 44, y: y + 1), size: 13, weight: .semibold, color: .black)
    text("Page 2 of 4", at: CGPoint(x: origin.x + 44, y: y + 19), size: 11, color: .gray)
    y += 44
    ctx.setFillColor(NSColor(white: 0, alpha: 0.1).cgColor); ctx.fill(CGRect(x: origin.x + 10, y: y + 4, width: width - 20, height: 1)); y += 9

    for (icon, title, key, highlighted) in rows {
        if title == "-" {
            ctx.setFillColor(NSColor(white: 0, alpha: 0.1).cgColor); ctx.fill(CGRect(x: origin.x + 10, y: y + 5, width: width - 20, height: 1)); y += 11; continue
        }
        let row = CGRect(x: origin.x + 5, y: y, width: width - 10, height: 24)
        if highlighted { roundedRect(ctx, row, radius: 5, fill: accent) }
        let fg: NSColor = highlighted ? .white : NSColor(white: 0.1, alpha: 1)
        if let icon { symbol(icon, in: CGRect(x: origin.x + 14, y: y + 5, width: 18, height: 14), color: fg) }
        text(title, at: CGPoint(x: origin.x + 40, y: y + 4), size: 13, color: fg)
        if let key { text(key, at: CGPoint(x: origin.x + width - 16, y: y + 4), size: 13, color: highlighted ? .white : .gray, align: .right, width: 80) }
        if title == "Open at Login" { symbol("checkmark", in: CGRect(x: origin.x + width - 32, y: y + 6, width: 14, height: 12), color: fg, weight: .semibold) }
        y += 24
    }
}

func drawHero() {
    let size = CGSize(width: 1280, height: 720)
    let doc = makeSampleDocument()
    render("hero.png", size) { ctx in
        let canvas = CGRect(origin: .zero, size: size)
        gradientBackground(ctx, canvas, radius: 28)

        // Menu bar strip with the PDFMark icon selected.
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: canvas, cornerWidth: 28, cornerHeight: 28, transform: nil)); ctx.clip()
        ctx.setFillColor(NSColor(white: 1, alpha: 0.22).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 30))
        ctx.restoreGState()
        let iconX: CGFloat = 930
        roundedRect(ctx, CGRect(x: iconX - 6, y: 4, width: 30, height: 22), radius: 5, fill: NSColor(white: 1, alpha: 0.3))
        symbol("bookmark", in: CGRect(x: iconX, y: 7, width: 18, height: 16), color: .white, weight: .medium)
        for (i, s) in ["wifi", "battery.75percent", "magnifyingglass"].enumerated() {
            symbol(s, in: CGRect(x: 985 + CGFloat(i) * 38, y: 7, width: 22, height: 15), color: .white)
        }
        text("Mon 17 Nov  09:41", at: CGPoint(x: 1256, y: 6), size: 13, weight: .medium, color: .white, align: .right, width: 140)

        // Preview-like window with a two-page spread.
        let win = CGRect(x: 48, y: 78, width: 820, height: 600)
        roundedRect(ctx, win, radius: 14, fill: NSColor(white: 0.93, alpha: 1), shadow: (18, 40, 0.4))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: win, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.clip()
        ctx.setFillColor(NSColor(white: 0.985, alpha: 1).cgColor); ctx.fill(CGRect(x: win.minX, y: win.minY, width: win.width, height: 52))
        ctx.setFillColor(NSColor(white: 0, alpha: 0.08).cgColor); ctx.fill(CGRect(x: win.minX, y: win.minY + 52, width: win.width, height: 1))
        ctx.restoreGState()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            ctx.setFillColor(c.cgColor); ctx.fillEllipse(in: CGRect(x: win.minX + 20 + CGFloat(i) * 20, y: win.minY + 20, width: 12, height: 12))
        }
        text("Deep Reading.pdf", at: CGPoint(x: win.minX + 100, y: win.minY + 10), size: 13, weight: .semibold, color: .black)
        text("Page 2 of 4", at: CGPoint(x: win.minX + 100, y: win.minY + 27), size: 11, color: .gray)

        let pageH: CGFloat = 520, pageW = pageH * 595 / 842
        let total = pageW * 2 + 16
        let px = win.midX - total / 2, py = win.minY + 52 + (win.height - 52 - pageH) / 2
        drawPage(ctx, doc.page(at: 0)!, in: CGRect(x: px, y: py, width: pageW, height: pageH))
        drawPage(ctx, doc.page(at: 1)!, in: CGRect(x: px + pageW + 16, y: py, width: pageW, height: pageH))

        drawMenu(ctx, at: CGPoint(x: iconX - 12, y: 32))
    }
}

// MARK: - How it works

func drawSteps() {
    let size = CGSize(width: 1200, height: 340)
    render("how-it-works.png", size) { ctx in
        let canvas = CGRect(origin: .zero, size: size)
        roundedRect(ctx, canvas, radius: 24, fill: NSColor(srgbRed: 0.965, green: 0.968, blue: 0.985, alpha: 1))
        let steps: [(String, String, String)] = [
            ("Read in Preview", "Open any PDF and scroll to the page you care about.", "preview"),
            ("Click the menu-bar icon", "Bookmark the page or drop a comment exactly where you want it.", "menu"),
            ("Saved into the PDF", "A real outline bookmark and note — visible in every PDF app.", "result"),
        ]
        let cardW: CGFloat = 330, gap: CGFloat = 60
        let startX = (size.width - (cardW * 3 + gap * 2)) / 2
        for (i, step) in steps.enumerated() {
            let card = CGRect(x: startX + CGFloat(i) * (cardW + gap), y: 36, width: cardW, height: 268)
            roundedRect(ctx, card, radius: 18, fill: .white, shadow: (6, 18, 0.12))
            // Illustration area
            let art = CGRect(x: card.minX + 20, y: card.minY + 20, width: card.width - 40, height: 130)
            roundedRect(ctx, art, radius: 12, fill: NSColor(srgbRed: 0.93, green: 0.94, blue: 0.99, alpha: 1))
            switch step.2 {
            case "preview":
                let page = CGRect(x: art.midX - 40, y: art.minY + 16, width: 80, height: 100)
                roundedRect(ctx, page, radius: 4, fill: .white, shadow: (3, 8, 0.15))
                for l in 0..<6 { ctx.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor); ctx.fill(CGRect(x: page.minX + 10, y: page.minY + 16 + CGFloat(l) * 12, width: l % 3 == 2 ? 40 : 60, height: 4)) }
                symbol("magnifyingglass", in: CGRect(x: page.maxX - 14, y: page.maxY - 34, width: 40, height: 36), color: indigoTop, weight: .semibold)
            case "menu":
                roundedRect(ctx, CGRect(x: art.minX, y: art.minY, width: art.width, height: 26), radius: 0, fill: NSColor(white: 1, alpha: 0.7))
                roundedRect(ctx, CGRect(x: art.midX - 14, y: art.minY + 3, width: 28, height: 20), radius: 5, fill: NSColor(white: 0, alpha: 0.1))
                symbol("bookmark", in: CGRect(x: art.midX - 9, y: art.minY + 5, width: 18, height: 16), color: .black, weight: .medium)
                let m = CGRect(x: art.midX - 80, y: art.minY + 30, width: 160, height: 88)
                roundedRect(ctx, m, radius: 8, fill: .white, shadow: (4, 10, 0.18))
                for (j, (ic, t)) in [("bookmark", "Bookmark This Page"), ("text.bubble", "Add Comment…"), ("list.bullet.rectangle", "Show All Comments…")].enumerated() {
                    let row = CGRect(x: m.minX + 4, y: m.minY + 6 + CGFloat(j) * 26, width: m.width - 8, height: 24)
                    if j == 0 { roundedRect(ctx, row, radius: 4, fill: accent) }
                    let fg: NSColor = j == 0 ? .white : .black
                    symbol(ic, in: CGRect(x: row.minX + 6, y: row.minY + 6, width: 14, height: 12), color: fg)
                    text(t, at: CGPoint(x: row.minX + 26, y: row.minY + 5), size: 11, color: fg)
                }
            default:
                let page = CGRect(x: art.midX - 40, y: art.minY + 16, width: 80, height: 100)
                roundedRect(ctx, page, radius: 4, fill: .white, shadow: (3, 8, 0.15))
                for l in 0..<6 { ctx.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor); ctx.fill(CGRect(x: page.minX + 10, y: page.minY + 16 + CGFloat(l) * 12, width: l % 3 == 2 ? 30 : 46, height: 4)) }
                upright(ctx, CGRect(x: page.maxX - 24, y: page.minY, width: 16, height: 30)) { MarkerArt.drawRibbon(in: $0, context: ctx) }
                upright(ctx, CGRect(x: page.maxX - 12, y: page.minY + 50, width: 30, height: 30)) { MarkerArt.drawNote(in: $0, color: noteColors[0].1, context: ctx) }
            }
            // Number + text
            let n = CGRect(x: card.minX + 20, y: art.maxY + 18, width: 26, height: 26)
            ctx.setFillColor(indigoTop.cgColor); ctx.fillEllipse(in: n)
            text("\(i + 1)", at: CGPoint(x: n.midX, y: n.minY + 4), size: 14, weight: .bold, color: .white, align: .center, width: 26)
            text(step.0, at: CGPoint(x: card.minX + 56, y: art.maxY + 20), size: 16, weight: .semibold, color: .black)
            text(step.1, at: CGPoint(x: card.minX + 20, y: art.maxY + 54), size: 13, color: NSColor(white: 0.35, alpha: 1), width: card.width - 40)
            if i < 2 {
                symbol("chevron.right", in: CGRect(x: card.maxX + gap / 2 - 10, y: card.midY - 12, width: 20, height: 24), color: NSColor(white: 0.6, alpha: 1), weight: .bold)
            }
        }
    }
}

// MARK: - Markers

func drawMarkers() {
    let size = CGSize(width: 1200, height: 260)
    render("markers.png", size) { ctx in
        let canvas = CGRect(origin: .zero, size: size)
        roundedRect(ctx, canvas, radius: 24, fill: NSColor(srgbRed: 0.965, green: 0.968, blue: 0.985, alpha: 1))
        // A page corner with the ribbon.
        let page = CGRect(x: 50, y: 40, width: 220, height: 180)
        roundedRect(ctx, page, radius: 6, fill: .white, shadow: (4, 12, 0.12))
        for l in 0..<6 { ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor); ctx.fill(CGRect(x: page.minX + 22, y: page.minY + 40 + CGFloat(l) * 20, width: l % 3 == 2 ? 90 : 130, height: 6)) }
        upright(ctx, CGRect(x: page.maxX - 70, y: page.minY, width: 44, height: 80)) { MarkerArt.drawRibbon(in: $0, context: ctx) }
        text("Bookmark ribbon", at: CGPoint(x: page.midX, y: page.maxY + 8), size: 13, weight: .medium, color: NSColor(white: 0.3, alpha: 1), align: .center, width: 220)

        let startX: CGFloat = 340, step: CGFloat = 135
        for (i, (name, color)) in noteColors.enumerated() {
            let r = CGRect(x: startX + CGFloat(i) * step, y: 74, width: 76, height: 76)
            upright(ctx, r) { MarkerArt.drawNote(in: $0, color: color, context: ctx) }
            text(name, at: CGPoint(x: r.midX, y: r.maxY + 16), size: 13, weight: .medium, color: NSColor(white: 0.3, alpha: 1), align: .center, width: 120)
        }
        text("Comment notes", at: CGPoint(x: startX + step * 2.5 + 38, y: 210), size: 13, weight: .medium, color: NSColor(white: 0.55, alpha: 1), align: .center, width: 300)
    }
}

// MARK: - Icon

func drawIcon() {
    let src = URL(fileURLWithPath: CommandLine.arguments[2])
    let img = NSImage(contentsOf: src)!
    render("icon.png", CGSize(width: 256, height: 256)) { _ in
        img.draw(in: CGRect(x: 0, y: 0, width: 256, height: 256), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

drawHero()
drawSteps()
drawMarkers()
drawIcon()
