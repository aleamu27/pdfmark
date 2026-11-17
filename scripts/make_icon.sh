#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make_icon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
cp "$ROOT/scripts/make_icon.swift" "$TMP/main.swift"
swiftc -O "$TMP/main.swift" "$ROOT/Sources/PDFMark/MarkerArt.swift" -o "$TMP/make_icon"
"$TMP/make_icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
cp "$TMP/AppIcon.iconset/icon_512x512@2x.png" "$ROOT/Resources/AppIcon.png"
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
