import AppKit
import PDFKit
import SwiftUI

/// Renders page thumbnails *without* annotations (existing notes are drawn as
/// separate markers on top, so a note being moved isn't shown twice).
final class PageThumbnails {
    let document: PDFDocument
    private var cache: [Int: NSImage] = [:]

    init(document: PDFDocument) {
        self.document = document
    }

    var pageCount: Int { document.pageCount }

    func pageSize(_ page: Int) -> CGSize {
        document.page(at: page - 1)?.bounds(for: .cropBox).size ?? CGSize(width: 595, height: 842)
    }

    func image(for page: Int, size: CGSize) -> NSImage {
        if let cached = cache[page] { return cached }
        guard let pdfPage = document.page(at: page - 1) else { return NSImage() }
        let previous = pdfPage.displaysAnnotations
        pdfPage.displaysAnnotations = false
        let image = pdfPage.thumbnail(of: NSSize(width: size.width * 2, height: size.height * 2), for: .cropBox)
        pdfPage.displaysAnnotations = previous
        cache[page] = image
        return image
    }
}

enum Spread {
    /// Steps a run of pages one "spread" back/forward, keeping its size.
    static func shift(_ spread: [Int], by direction: Int, total: Int) -> [Int] {
        let count = max(spread.count, 1)
        let first = min(max((spread.first ?? 1) + direction * count, 1), max(total - count + 1, 1))
        return Array(first...min(first + count - 1, total))
    }

    /// A two-page view containing `page` (or just the page for 1-page docs).
    static func pair(containing page: Int, total: Int) -> [Int] {
        guard total > 1 else { return [page] }
        return page < total ? [page, page + 1] : [page - 1, page]
    }

    static func label(_ spread: [Int], total: Int) -> String {
        let range = spread.count > 1 ? "\(spread.first!)–\(spread.last!)" : "\(spread.first ?? 1)"
        return "Pages \(range) of \(total)"
    }
}

/// The given pages side by side, scaled to fit, with a note marker the user can
/// click or drag anywhere on any of them. Other notes are shown as small faded
/// markers so you can see what's already there.
struct PagePicker: View {
    let thumbnails: PageThumbnails
    let spread: [Int]
    @Binding var placement: CommentPlacement
    let color: NoteColor
    var otherNotes: [CommentRecord] = []
    let area: CGSize

    private let spacing: CGFloat = 12
    @State private var isDragging = false

    private struct Slot { let page: Int; let rect: CGRect }

    private var slots: [Slot] {
        let sizes = spread.map { thumbnails.pageSize($0) }
        let totalWidth = sizes.reduce(0) { $0 + $1.width }
        let gaps = spacing * CGFloat(max(sizes.count - 1, 0))
        let maxHeight = sizes.map(\.height).max() ?? 1
        let scale = min(area.height / maxHeight, (area.width - gaps) / max(totalWidth, 1))
        var x = (area.width - (totalWidth * scale + gaps)) / 2
        return zip(spread, sizes).map { page, size in
            let w = size.width * scale, h = size.height * scale
            defer { x += w + spacing }
            return Slot(page: page, rect: CGRect(x: x, y: (area.height - h) / 2, width: w, height: h))
        }
    }

    var body: some View {
        let slots = self.slots
        ZStack(alignment: .topLeading) {
            ForEach(slots, id: \.page) { slot in
                let selected = slot.page == placement.page
                Image(nsImage: thumbnails.image(for: slot.page, size: slot.rect.size))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: slot.rect.width, height: slot.rect.height)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: selected ? 2 : 0.5)
                    )
                    .shadow(color: .black.opacity(selected ? 0.25 : 0.12), radius: selected ? 6 : 3, y: 2)
                    .overlay(alignment: .bottom) {
                        Text("\(slot.page)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial), in: Capsule())
                            .padding(6)
                    }
                    .position(x: slot.rect.midX, y: slot.rect.midY)

                ForEach(otherNotes.filter { $0.page == slot.page }) { note in
                    NoteBadge(color: note.color, size: 14)
                        .opacity(0.7)
                        .position(x: slot.rect.minX + note.point.x * slot.rect.width,
                                  y: slot.rect.minY + note.point.y * slot.rect.height)
                }
            }

            if let slot = slots.first(where: { $0.page == placement.page }) {
                NoteMarker(color: color)
                    .position(x: slot.rect.minX + placement.point.x * slot.rect.width,
                              y: slot.rect.minY + placement.point.y * slot.rect.height)
                    .scaleEffect(isDragging ? 1.18 : 1)
                    .allowsHitTesting(false)
                    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.75), value: placement)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isDragging)
            }
        }
        .frame(width: area.width, height: area.height)
        .contentShape(Rectangle())
        .coordinateSpace(name: "pagePicker")
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("pagePicker"))
                .onChanged {
                    if !isDragging { isDragging = true; NSCursor.closedHand.set() }
                    move(to: $0.location, in: slots)
                }
                .onEnded { _ in
                    isDragging = false
                    NSCursor.openHand.set()
                }
        )
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeInOut(duration: 0.22), value: spread)
    }

    /// Snaps the marker onto the page under the pointer (or the nearest page if
    /// the pointer is in a gap) and records its normalized position.
    private func move(to location: CGPoint, in slots: [Slot]) {
        guard let slot = slots.first(where: { $0.rect.contains(location) })
                ?? slots.min(by: { distance(location, $0.rect) < distance(location, $1.rect) }) else { return }
        let x = min(max((location.x - slot.rect.minX) / slot.rect.width, 0), 1)
        let y = min(max((location.y - slot.rect.minY) / slot.rect.height, 0), 1)
        placement = CommentPlacement(page: slot.page, point: CGPoint(x: x, y: y))
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}

/// The note being placed: the same badge that will be drawn on the page,
/// enlarged and lifted with a shadow so it stands out on any page content.
struct NoteMarker: View {
    let color: NoteColor

    var body: some View {
        NoteBadge(color: color, size: 30)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

/// A row of color swatches for picking a note color.
struct NoteColorPicker: View {
    @Binding var selection: NoteColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NoteColor.allCases) { color in
                Button { selection = color } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().strokeBorder(selection == color ? Color.accentColor : .clear, lineWidth: 2))
                        .scaleEffect(selection == color ? 1.08 : 1)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.name)
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: selection)
            }
        }
    }
}

/// Lays out the picker with ‹ › page navigation, on a subtle backdrop.
struct PagePickerCard: View {
    let thumbnails: PageThumbnails
    @Binding var spread: [Int]
    @Binding var placement: CommentPlacement
    let color: NoteColor
    var otherNotes: [CommentRecord] = []
    let height: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                PagePicker(
                    thumbnails: thumbnails,
                    spread: spread,
                    placement: $placement,
                    color: color,
                    otherNotes: otherNotes,
                    area: CGSize(width: geo.size.width - 24, height: geo.size.height - 20)
                )
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(height: height)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Label("Click or drag to place the note — on either page", systemImage: "hand.point.up.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled((spread.first ?? 1) <= 1)
                Text(Spread.label(spread, total: thumbnails.pageCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled((spread.last ?? 1) >= thumbnails.pageCount)
            }
            .buttonStyle(.borderless)
        }
    }

    private func shift(_ direction: Int) {
        spread = Spread.shift(spread, by: direction, total: thumbnails.pageCount)
        if !spread.contains(placement.page) {
            placement.page = spread[0]
        }
    }
}

/// The note badge as a SwiftUI view — identical to what's drawn on the page.
struct NoteBadge: View {
    let color: NoteColor
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: MarkerArt.noteImage(color: color.nsColor, size: size))
            .frame(width: size, height: size)
    }
}
