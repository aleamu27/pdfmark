#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="PDFMark"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"
CONFIGURATION="${1:-debug}"

echo "Building ($CONFIGURATION)..."
swift build --configuration "$CONFIGURATION" --package-path "$ROOT"

BIN_PATH="$ROOT/.build/$CONFIGURATION/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Sign with a STABLE identity so macOS keeps the granted Accessibility
# permission across rebuilds. Ad-hoc (`--sign -`) has no stable designated
# requirement — TCC keys the grant to the binary's cdhash, which changes every
# build, so the permission was silently revoked each time. An Apple Development
# certificate gives a constant designated requirement (bundle id + cert), so the
# grant sticks. Falls back to ad-hoc only if no such identity exists.
IDENTITY_HASH="$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')"
if [ -n "$IDENTITY_HASH" ]; then
  echo "Signing with Apple Development identity $IDENTITY_HASH"
  codesign --force --sign "$IDENTITY_HASH" "$APP_BUNDLE"
else
  echo "No Apple Development identity found; falling back to ad-hoc (permissions will not persist across rebuilds)"
  codesign --force --sign - "$APP_BUNDLE"
fi

# Re-register with Launch Services so it picks up the NSServices entry (the
# Services menu is driven by LS's cache, which doesn't always notice an
# in-place rebuild of an unsigned dev app on its own).
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
