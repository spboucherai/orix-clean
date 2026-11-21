#!/usr/bin/env bash
# ORIX Clean — Scripts/package.sh
# Description: Builds the distribution artifacts from the notarized, stapled dist/ORIX Clean.app:
#              a signed DMG (background artwork, Applications shortcut), a ZIP, SHA-256 checksums and release metadata.
#              The DMG must then be notarized: Scripts/notarize.sh dist/ORIXClean-<version>.dmg dmg
# Author: Simon-Pierre Boucher — contact@spboucher.ai
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/ORIX Clean.app"
[[ -d "$APP" ]] || { echo "ERROR: $APP not found." >&2; exit 1; }
xcrun stapler validate "$APP" >/dev/null 2>&1 || { echo "ERROR: the app is not notarized and stapled yet (Scripts/notarize.sh)." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="dist/ORIXClean-$VERSION.dmg"; ZIP="dist/ORIXClean-$VERSION.zip"
IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)"
rm -f "$DMG" "$ZIP"
swift Scripts/dmg-background.swift build/dmg-background.png >/dev/null
STAGE="$(mktemp -d)"; ditto "$APP" "$STAGE/ORIX Clean.app"
create-dmg --volname "ORIX Clean $VERSION" --background build/dmg-background.png --window-pos 200 140 --window-size 660 420 \
  --icon-size 128 --icon "ORIX Clean.app" 170 205 --app-drop-link 490 205 --hide-extension "ORIX Clean.app" --no-internet-enable \
  "$DMG" "$STAGE" >/dev/null 2>&1 || { echo "create-dmg failed; falling back to a plain image" >&2; ln -s /Applications "$STAGE/Applications"; hdiutil create -volname "ORIX Clean $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null; }
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "built $DMG and $ZIP (version $VERSION build $BUILD). Notarize the DMG next, then run: Scripts/package.sh --finalize"
