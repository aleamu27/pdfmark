#!/bin/bash
# Builds a distributable PDFMark: a universal (Apple Silicon + Intel) app with
# no dependencies, packaged as dist/PDFMark-<version>.dmg (drag-to-Applications)
# and dist/PDFMark-<version>.zip.
#
# Signing / notarization (so it opens on other Macs without warnings):
#   - With a "Developer ID Application" certificate in your keychain, the app is
#     signed with it (hardened runtime + secure timestamp).
#   - If NOTARY_PROFILE is also set, it's notarized and stapled. Create the
#     profile once with:
#       xcrun notarytool store-credentials pdfmark --apple-id <id> --team-id <team>
#     then run:  NOTARY_PROFILE=pdfmark ./scripts/release.sh
#   - Without a Developer ID it's ad-hoc signed: it works, but people who
#     download it must allow it once (see README → Installing).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PDFMark"
DIST="$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

echo "==> Building $APP_NAME $VERSION (universal, release)"
swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64
BIN="$(swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

echo "==> Assembling app bundle"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
strip -rSTx "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true

IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  echo "==> Signing with $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  echo "==> No Developer ID certificate found: ad-hoc signing (users must allow the app once)"
  codesign --force --options runtime --sign - "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

notarize() {
  if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing $(basename "$1")"
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
    return 0
  fi
  return 1
}

# Notarize the app (via a zip), staple the ticket, then package.
if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  notarize "$DIST/notarize.zip"
  xcrun stapler staple "$APP"
  rm "$DIST/notarize.zip"
fi

echo "==> Creating $(basename "$ZIP")"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Creating $(basename "$DMG")"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if notarize "$DMG"; then xcrun stapler staple "$DMG"; fi
fi

echo
echo "Done:"
echo "  $DMG"
echo "  $ZIP"
lipo -archs "$APP/Contents/MacOS/$APP_NAME" | sed 's/^/  architectures: /'
