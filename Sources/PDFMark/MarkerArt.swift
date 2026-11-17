import AppKit

/// The artwork PDFMark puts on pages: the bookmark ribbon and the note badge.
///
/// Drawn with plain Core Graphics paths (no images, no fonts) so that when
/// PDFKit bakes them into the annotation's appearance stream on save they stay
/// crisp vector shapes at any zoom — in Preview and every other PDF viewer.
/// The same drawing is reused for the markers in PDFMark's own windows, so what
/// you place is exactly what ends up on the page.
enum MarkerArt {
    // MARK: Note badge

    /// A rounded "squircle" in the note color with a white speech bubble inside.
    /// `rect` is in a y-up coordinate space (PDF page space or an unflipped image).
    static func drawNote(in rect: CGRect, color: NSColor, context ctx: CGContext) {
        let base = (color.usingColorSpace(.sRGB) ?? color)
        let s = min(rect.width, rect.height)
        let badge = CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s).insetBy(dx: s * 0.07, dy: s * 0.07)
        let radius = badge.width * 0.3
        let badgePath = CGPath(roundedRect: badge, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Soft drop shadow + white rim, so the badge reads on any page content.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.03), blur: s * 0.08, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(CGPath(roundedRect: badge.insetBy(dx: -s * 0.04, dy: -s * 0.04), cornerWidth: radius * 1.12, cornerHeight: radius * 1.12, transform: nil))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Vertical gradient: a touch lighter on top, a touch deeper below.
        ctx.saveGState()
        ctx.addPath(badgePath)
        ctx.clip()
        let top = base.blended(withFraction: 0.18, of: .white) ?? base
        let bottom = base.blended(withFraction: 0.12, of: .black) ?? base
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: badge.midX, y: badge.maxY), end: CGPoint(x: badge.midX, y: badge.minY), options: [])
        }
        ctx.restoreGState()

        // White speech bubble with a tail at the bottom-left.
        let bw = badge.width * 0.6, bh = badge.height * 0.44
        let bubble = CGRect(x: badge.midX - bw / 2, y: badge.midY - bh / 2 + badge.height * 0.06, width: bw, height: bh)
        let br = bh * 0.38
        let glyph = CGMutablePath()
        glyph.addRoundedRect(in: bubble, cornerWidth: br, cornerHeight: br)
        glyph.move(to: CGPoint(x: bubble.minX + bw * 0.2, y: bubble.minY + 0.5))
        glyph.addLine(to: CGPoint(x: bubble.minX + bw * 0.14, y: bubble.minY - bh * 0.42))
        glyph.addLine(to: CGPoint(x: bubble.minX + bw * 0.48, y: bubble.minY + 0.5))
        glyph.closeSubpath()
        ctx.saveGState()
        ctx.addPath(glyph)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Two "text" lines inside the bubble.
        ctx.saveGState()
        ctx.setStrokeColor(bottom.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(max(s * 0.055, 0.6))
        ctx.setLineCap(.round)
        let inset = bw * 0.22
        let y1 = bubble.midY + bh * 0.14, y2 = bubble.midY - bh * 0.16
        ctx.move(to: CGPoint(x: bubble.minX + inset, y: y1)); ctx.addLine(to: CGPoint(x: bubble.maxX - inset, y: y1))
        ctx.move(to: CGPoint(x: bubble.minX + inset, y: y2)); ctx.addLine(to: CGPoint(x: bubble.maxX - inset * 1.9, y: y2))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Bookmark ribbon

    static let ribbonRed = NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)

    /// A bookmark ribbon hanging from the top of `rect` with a V-notch at the
    /// bottom, a subtle fold shadow where it meets the page edge, and a soft
    /// left-to-right shading so it looks like folded fabric, not a flat block.
    static func drawRibbon(in rect: CGRect, context ctx: CGContext) {
        let b = rect.insetBy(dx: rect.width * 0.1, dy: 0)
        let b2 = CGRect(x: b.minX, y: b.minY + rect.height * 0.04, width: b.width, height: b.height - rect.height * 0.04)
        let notch = b2.height * 0.2
        let corner = b2.width * 0.12

        let path = CGMutablePath()
        path.move(to: CGPoint(x: b2.minX, y: b2.maxY))
        path.addLine(to: CGPoint(x: b2.maxX, y: b2.maxY))
        path.addLine(to: CGPoint(x: b2.maxX, y: b2.minY + corner))
        path.addQuadCurve(to: CGPoint(x: b2.maxX - corner, y: b2.minY + corner * 0.4), control: CGPoint(x: b2.maxX, y: b2.minY))
        path.addLine(to: CGPoint(x: b2.midX, y: b2.minY + notch))
        path.addLine(to: CGPoint(x: b2.minX + corner, y: b2.minY + corner * 0.4))
        path.addQuadCurve(to: CGPoint(x: b2.minX, y: b2.minY + corner), control: CGPoint(x: b2.minX, y: b2.minY))
        path.closeSubpath()

        // Shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.2), blur: 3, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(ribbonRed.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Fabric shading
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let light = ribbonRed.blended(withFraction: 0.15, of: .white) ?? ribbonRed
        let dark = ribbonRed.blended(withFraction: 0.22, of: .black) ?? ribbonRed
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        if let g = CGGradient(colorsSpace: space, colors: [light.cgColor, ribbonRed.cgColor, dark.cgColor] as CFArray, locations: [0, 0.45, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: b2.minX, y: b2.midY), end: CGPoint(x: b2.maxX, y: b2.midY), options: [])
        }
        // Fold at the top edge, as if the ribbon tucks behind the page. Opaque
        // colors only: PDF shadings can't carry alpha (it renders as black).
        let foldHeight = max(b2.height * 0.07, 2)
        ctx.setFillColor((ribbonRed.blended(withFraction: 0.4, of: .black) ?? dark).cgColor)
        ctx.fill(CGRect(x: b2.minX, y: b2.maxY - foldHeight, width: b2.width, height: foldHeight))
        ctx.setFillColor(light.cgColor)
        ctx.fill(CGRect(x: b2.minX, y: b2.maxY - foldHeight - 0.6, width: b2.width, height: 0.6))
        // Stitched highlight line down the left side.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(0.6)
        ctx.setLineDash(phase: 0, lengths: [1.6, 1.2])
        ctx.move(to: CGPoint(x: b2.minX + b2.width * 0.18, y: b2.maxY - b2.height * 0.12))
        ctx.addLine(to: CGPoint(x: b2.minX + b2.width * 0.18, y: b2.minY + notch + 2))
        ctx.move(to: CGPoint(x: b2.maxX - b2.width * 0.18, y: b2.maxY - b2.height * 0.12))
        ctx.addLine(to: CGPoint(x: b2.maxX - b2.width * 0.18, y: b2.minY + notch + 2))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Images for the UI

    private static var noteCache: [String: NSImage] = [:]

    static func noteImage(color: NSColor, size: CGFloat) -> NSImage {
        let key = "\(color.description)-\(size)"
        if let cached = noteCache[key] { return cached }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawNote(in: rect, color: color, context: ctx)
            return true
        }
        noteCache[key] = image
        return image
    }

    static func ribbonImage(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawRibbon(in: rect, context: ctx)
            return true
        }
    }
}
