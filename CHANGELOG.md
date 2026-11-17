# Changelog

## 0.2 — look & distribution

### Added
- **App icon**, and a downloadable **DMG** (drag to Applications) / zip built by
  `scripts/release.sh`: one universal app (Apple Silicon + Intel), no
  dependencies. Signs + notarizes automatically when a Developer ID is present.
- **Open at Login** in the menu.
- Double-clicking the app while it's running opens its menu; launching it shows
  a hint pointing at the menu-bar icon.
- Warning when run from Downloads/a disk image (macOS would forget permissions).
- **Restart PDFMark** button in the introduction, which updates live when
  Accessibility access is granted.

### Changed
- **New on-page artwork**: notes are a modern rounded color badge with a speech
  bubble (instead of the viewer's default sticky-note icon); the bookmark ribbon
  has fabric shading and a fold. The same badge is used in PDFMark's panels.
- Smoother UI: panels and toasts fade/glide in and out, the menu-bar icon
  cross-fades, the note marker springs while dragging, and the menu opens
  instantly (document info is read once and cached).
- Changing a note's color redraws its icon in the new color.

### Fixed
- Introduction window text was cut off with "…".
- Removed the debug log written to `/tmp`.

## Unreleased — comments

### Added
- **Comments**: add sticky-note comments (standard PDF `/Text` annotations) to the
  page you're reading in Preview. They sit on top of the page, never alter its
  content, and open a popup with your text in any PDF viewer.
- **Place notes anywhere on either page**: the comment panel shows the pages on
  screen (both halves of a two-page spread) as thumbnails; click or drag the note
  to the exact spot. ‹ › browse to other pages.
- **Note colors**: yellow, orange, red, green, blue, purple (last choice remembered).
- **Comments window** (*Show All Comments…*): all notes grouped by page, incl.
  notes made in Preview; search; edit text; change color; move to any page;
  *Show in Preview*; *Copy All* as text; delete one (⌫) or all — always
  with a "Delete this comment?" confirmation.
- **Undo** for every change (bookmark, comment, edit, move, delete, remove
  bookmark): last 20 versions per document, from the menu or the comments window.
- **Remove Bookmark** and **Go to Bookmark — Page N** in the menu.
- **Confirmation toasts** under the menu-bar icon ("Comment added to page 92"),
  and readable error messages instead of only a red icon.
- Paste/copy/cut/select-all/undo (⌘V ⌘C ⌘X ⌘A ⌘Z) work in PDFMark's text fields.

### Changed
- Clicking the menu-bar icon opens a menu (document name + current page at the
  top) instead of immediately starting a bookmark.
- After any change the PDF is reopened in Preview at the same page, so the change
  is visible immediately. Preview's window is closed *before* the file is written,
  so Preview saves its own edits first and nothing gets overwritten.
- Page detection uses Preview's list of on-screen pages (`AXVisibleChildren`);
  the old geometry-only method always returned page 1 on recent macOS.
- Missing Accessibility access now opens the introduction window explaining it.
- Redesigned panels and introduction text.

### Fixed
- Setting a bookmark no longer deletes other annotations by PDFMark (only the
  ribbon stamp is removed).
- Deleting a note also removes its popup annotation (and cleans up orphans).
