#!/bin/bash
# Regenerates the README illustrations in docs/images/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
cp "$ROOT/scripts/make_readme_images.swift" "$TMP/main.swift"
swiftc -O "$TMP/main.swift" "$ROOT/Sources/PDFMark/MarkerArt.swift" -o "$TMP/make_readme_images"
"$TMP/make_readme_images" "$ROOT/docs/images" "$ROOT/Resources/AppIcon.png"
rm -rf "$TMP"
