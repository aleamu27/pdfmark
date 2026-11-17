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
4. **Reloads & scrolls** — PDFMark closes the document's Preview window, reopens
   the file (so the change is visible immediately) and asks Preview, via AX, to
   scroll back to the same page.

Only **one PDFMark bookmark is kept per document** — setting a new one cleanly
removes the previous outline entry and ribbon first, without ever touching the
document's own pre-existing table of contents.

### Comments

Click the menu-bar icon → **Add Comment…** while reading. The comment panel
shows the pages on screen (both halves of a two-page spread) — **click or drag
the note** to the exact spot you want, on either page, pick a color, type, and
press **⌘↩**. PDFMark writes a standard PDF **note annotation** (`/Subtype /Text`):
a small icon on top of the page that never alters its content and opens a popup
with your text in Preview and any other viewer.

**Show All Comments…** opens a comments window for the document:

- every note grouped by page (including notes made in Preview), with search;
- edit the text, change the color, or **move a note to another page**;
- *Show in Preview* jumps to the note's page; *Copy All* copies every comment as text;
- delete one note (⌫) or all of them — PDFMark asks for confirmation first.

### Undo & safety

Every change PDFMark makes — bookmark, comment, edit, move, delete — can be
undone from the menu (*Undo “…”*) or the comments window. Before each change a
copy of the PDF is kept in `~/Library/Application Support/PDFMark/Undo` (last 20
per document). Preview's window is closed while the file changes (so Preview
saves its own edits first and neither side overwrites the other), then the PDF
is reopened at the same page, so the change is visible immediately.

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

with $(w_r, h_r) = (24, 44)$ points and $m_r = 30$ points. PDFKit bakes the
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

### Look of the markers

The ribbon and the note icons are PDFMark's own vector artwork
(`MarkerArt.swift`), not the viewer's dated default sticky-note glyph. Notes are a
rounded badge in the note's color with a white speech bubble; the ribbon has a
soft fabric shading and a fold where it meets the page edge. Both are baked into
the annotation's appearance stream on save, so they look the same in Preview and
every other PDF viewer. The same drawing is used for the markers inside
PDFMark's own panels, and for the app icon (`scripts/make_icon.sh`).

> PDF shadings can't carry transparency (it renders as black), so the artwork
> uses only opaque gradients plus solid-alpha fills and shadows.

---

## Installing (for users)

1. Download `PDFMark-<version>.dmg`, open it and **drag PDFMark into Applications**.
   (Running it straight from Downloads or the disk image makes macOS forget its
   permissions — PDFMark warns about this.)
2. Open PDFMark from Applications. Until it is notarized by Apple, macOS will say
   it can't verify the developer the first time: click **Done**, then go to
   *System Settings → Privacy & Security*, scroll down and click **Open Anyway**.
   This is needed only once.
3. The introduction window walks you through granting **Accessibility** access.
   After switching it on, click **Restart PDFMark**.

Nothing else to install: it's one universal app (Apple Silicon + Intel) for
macOS 13 or later, using only system frameworks. Optional: *Open at Login* in the
menu.

## Releasing

```bash
./scripts/release.sh    # → dist/PDFMark-<version>.dmg and .zip (universal, release build)
```

With a **Developer ID Application** certificate in the keychain the app and DMG
are signed with it (hardened runtime); add `NOTARY_PROFILE=<profile>` to also
notarize and staple, which removes the "Open Anyway" step for users entirely:

```bash
xcrun notarytool store-credentials pdfmark --apple-id <apple-id> --team-id <team-id>
NOTARY_PROFILE=pdfmark ./scripts/release.sh
```

Without one, the release is ad-hoc signed. Bump `CFBundleShortVersionString` /
`CFBundleVersion` in `Resources/Info.plist` before each release. The release
uses bundle id `no.pdfmark.app`; `build.sh` dev builds use `no.pdfmark.app.dev2`,
so their Accessibility grants never interfere.

## Build & run (development)

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
3. Open a PDF in Preview, scroll to a page, **click the menu-bar icon** and pick
   *Bookmark This Page* or *Add Comment…*.
4. Confirm the page in the panel → the bookmark/comment is written and Preview jumps to it.

Clicking the menu-bar icon opens a menu showing the current document and page,
with *Bookmark This Page*, *Add Comment…*, *Show All Comments…*, *Go to
Bookmark*, *Remove Bookmark*, *Undo*, *Show Introduction…* and *Quit PDFMark*.

---

## Architecture

```
Sources/PDFMark/
├── PDFMarkApp.swift         # @main AppDelegate: menu-bar wiring, hotkey, flow orchestration
├── StatusIconController.swift # menu-bar item + success/error flash states
├── PreviewInspector.swift   # AX traversal: current file + page detection + scroll-to-page
├── BookmarkWriter.swift     # PDFKit: outline entry, ribbon annotation, single-bookmark logic
├── CommentStore.swift       # PDFKit: read/add/edit/move/delete note annotations
├── CommentPanel.swift       # the "new comment" panel (page picker, colors, text)
├── CommentsWindow.swift     # the comments window (list, search, inspector)
├── PagePicker.swift         # page thumbnails with a draggable note marker
├── MarkerArt.swift          # vector artwork for the ribbon + note badge (PDF and UI)
├── UndoHistory.swift        # per-document undo snapshots
├── Toast.swift              # small confirmation bubble under the menu-bar icon
├── EditingSupport.swift     # ⌘C/⌘V/⌘X/⌘A/⌘Z in a menu-bar-only app
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
- **Notarization** needs a paid Apple Developer account (Developer ID). Until
  then, downloaded copies need a one-time *Open Anyway* (see Installing), and
  because ad-hoc signatures change with every release, users re-grant
  Accessibility after updating.

## License

MIT — see [`LICENSE`](LICENSE).
