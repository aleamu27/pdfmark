// Renders PDFMark's app icon (Resources/AppIcon.icns) from code, reusing the
// exact ribbon and note artwork the app draws onto PDF pages.
// Usage: ./scripts/make_icon.sh   (compiles this together with MarkerArt.swift)
import AppKit

func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = CGFloat(pixels) / 1024
    ctx.scaleBy(x: k, y: k)

    // macOS icon grid: 824pt squircle centered in 1024, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(tilePath); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        NSColor(srgbRed: 0.36, green: 0.42, blue: 0.98, alpha: 1).cgColor,
        NSColor(srgbRed: 0.20, green: 0.22, blue: 0.62, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // A white page, slightly tilted, with "text" lines.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 500)
    ctx.rotate(by: -0.06)
    let page = CGRect(x: -230, y: -290, width: 460, height: 590)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(CGPath(roundedRect: page, cornerWidth: 28, cornerHeight: 28, transform: nil))
    ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.setFillColor(NSColor(srgbRed: 0.82, green: 0.84, blue: 0.9, alpha: 1).cgColor)
    for (i, w) in [250, 340, 260, 330, 220].enumerated() {
        ctx.addPath(CGPath(roundedRect: CGRect(x: -170, y: 150 - CGFloat(i) * 62, width: CGFloat(w), height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
    }
    ctx.fillPath()
    MarkerArt.drawRibbon(in: CGRect(x: 90, y: 140, width: 100, height: 160), context: ctx)
    ctx.restoreGState()

    // Note badge overlapping the page's bottom-right corner.
    MarkerArt.drawNote(in: CGRect(x: 580, y: 170, width: 250, height: 250),
                       color: NSColor(srgbRed: 1.00, green: 0.82, blue: 0.20, alpha: 1), context: ctx)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! renderIcon(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! renderIcon(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
