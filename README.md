# PDFMark

> A tiny macOS menu-bar app that drops a **real PDF outline bookmark** — plus a
> small red corner ribbon — onto whatever page you're currently viewing in
> **Preview.app**. One click, no fiddling with the PDF itself.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-black?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/UI-AppKit%20%2B%20PDFKit-blue" alt="AppKit + PDFKit">
  <img src="https://img.shields.io/badge/deps-zero-brightgreen" alt="Zero dependencies">
</p>

---

## Why

Preview can *show* PDFs beautifully, but it can't **add** persistent outline
bookmarks to an arbitrary document. PDFMark fills that gap: while you read in
Preview, hit the menu-bar icon, confirm the page, and PDFMark writes a genuine
`PDFOutline` entry back into the file — visible in Preview's table of contents
(`⌘⌥3`) and in every other PDF viewer, because it's baked into the document, not
stored in some sidecar database.

## What it does

```
┌──────────────┐        ┌────────────────────┐        ┌─────────────────────┐
│  Preview.app │        │      PDFMark        │        │   your-file.pdf     │
│  (you read)  │ ─AX──▶ │  detect page + file │ ─PDFKit▶ │  + outline entry    │
│              │ ◀reload─│  write bookmark     │        │  + corner ribbon 🔖 │
└──────────────┘        └────────────────────┘        └─────────────────────┘
```

1. **Detects the current page** in the frontmost Preview window using the macOS
   Accessibility (AX) API — no polling of Preview's window title, which is
   unreliable (see [Page detection](#page-detection-the-interesting-bit)).
2. **Shows a confirm panel** pre-filled with the guessed page number, so you can
   nudge it if needed.
3. **Writes the bookmark** straight into the PDF on disk via PDFKit:
   - a `PDFOutline` entry pointing at the page, and
   - a small red **ribbon annotation** in the top-right corner of that page.
4. **Reloads & scrolls** — Preview auto-reloads the externally-modified file, and
   PDFMark asks it (again via AX) to scroll the bookmarked page into view.

Only **one PDFMark bookmark is kept per document** — setting a new one cleanly
removes the previous outline entry and ribbon first, without ever touching the
document's own pre-existing table of contents.

---

## Page detection (the interesting bit)

Preview's window title (`AXTitle`, e.g. *"Side 3 av 28"*) looks tempting but is a
trap — it only reflects the live page transiently right after a scroll, then goes
stale. PDFMark instead works **geometrically**.

Inside the `AXScrollArea` that holds the `AXPage` children, let the scroll area's
visible frame have origin $(v_x, v_y)$ and height $v_h$. Its vertical center is

$$
c_y \;=\; v_y + \frac{v_h}{2}.
$$

Each page $P_i$ reports a position and size via `kAXPositionAttribute` /
`kAXSizeAttribute`, giving a vertical extent $[\,y^{\text{bot}}_i,\; y^{\text{top}}_i\,]$.
The current page is the one whose extent straddles that center line:

$$
p^\star \;=\; \Big\{\, P_i \;\big|\; y^{\text{bot}}_i \;\le\; c_y \;\le\; y^{\text{top}}_i \,\Big\}.
$$

This is robust across sidebar-on/off toggles and window resizes, where the title
heuristic falls apart.

## Ribbon placement

The visible marker is a custom `PDFAnnotation` whose bounding box, in the page's
media-box coordinates $(W_{\text{media}}, H_{\text{media}})$, is anchored to the
top-right corner with a fixed right margin $m_r$:

$$
\mathrm{ribbon} \;=\;
\big(\; W_{\text{media}} - m_r - w_r,\;\; H_{\text{media}} - h_r,\;\; w_r,\;\; h_r \;\big),
$$

with $(w_r, h_r) = (22, 46)$ points and $m_r = 30$ points. PDFKit bakes the
result of the annotation's `draw(with:in:)` into the saved appearance stream, so
the ribbon renders identically in **any** viewer afterwards — not just inside
PDFKit.

## Invisible tagging (so it's undoable)

PDFMark needs to find *its own* additions later without cluttering the document:

| Addition        | Tag                                             | Visible to user? |
| --------------- | ----------------------------------------------- | ---------------- |
| Outline entry   | zero-width space `\u{200B}` appended to label   | No               |
| Ribbon annotation | `userName = "PDFMark"` (the PDF `/T` field)   | No               |

These survive `PDFDocument.write(to:)`; a custom `documentAttributes` key was
tried first and does **not** persist, so it isn't used.

---

## Build & run

Requires macOS 13+ and a Swift toolchain (Xcode command-line tools).

```bash
./build.sh              # builds .build/, bundles build/PDFMark.app, code-signs it
open build/PDFMark.app  # launches into the menu bar
```

`build.sh` signs with a stable **Apple Development** identity when one is present
in your keychain (falling back to ad-hoc). This matters: TCC keys the
Accessibility grant to the binary's designated requirement, and a stable cert
keeps the grant alive across rebuilds instead of silently revoking it every time.

### First run

1. PDFMark lives in the **menu bar** (no Dock icon — it's an `LSUIElement`).
2. Grant **Accessibility** access when prompted
   (*System Settings → Privacy & Security → Accessibility*). This is required to
   read the current page from Preview.
   > ⚠️ `AXIsProcessTrusted()` caches its result for the process lifetime — if you
   > grant access while PDFMark is already running, **quit and relaunch** it.
3. Open a PDF in Preview, scroll to a page, and **click the menu-bar icon**.
4. Confirm the page in the panel → the bookmark is written and Preview jumps to it.

**Right-click** the menu-bar icon for *Show Introduction…* and *Quit PDFMark*.

---

## Architecture

```
Sources/PDFMark/
├── PDFMarkApp.swift         # @main AppDelegate: menu-bar wiring, hotkey, flow orchestration
├── StatusIconController.swift # menu-bar item + success/error flash states
├── PreviewInspector.swift   # AX traversal: current file + page detection + scroll-to-page
├── BookmarkWriter.swift     # PDFKit: outline entry, ribbon annotation, single-bookmark logic
├── ConfirmPanel.swift       # the "which page?" confirmation UI
└── OnboardingWindow.swift   # first-launch intro + live Accessibility status
```

- **Language / stack:** Swift, AppKit + PDFKit + ApplicationServices (AX), a
  sprinkle of SwiftUI for panel content. **No third-party dependencies.**
- **Build system:** Swift Package Manager executable target (`Package.swift`),
  hand-bundled into a `.app` by `build.sh` (no Xcode project).
- **`Spikes/`** holds standalone experiment scripts used while figuring out the AX
  and PDFKit behaviour — kept for reference, not part of the app build.

## Known limitations

- **Global hotkey (`⌥⌘B`)** is wired up but doesn't fire reliably on all setups
  (a modifier-remap / keyboard-driver quirk was never fully root-caused). The
  menu-bar click is the primary, reliable trigger.
- **Right-click Services menu** entry in Preview is registered but not honored by
  macOS — legacy `NSServices` appear to need a real Developer ID signature.
- **Distribution:** dev-signed only. No Developer ID signing / notarization yet,
  so this is a build-it-yourself utility for now.

## License

MIT — see [`LICENSE`](LICENSE).
