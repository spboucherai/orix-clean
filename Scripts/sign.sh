#!/usr/bin/env bash
# ORIX Clean — Scripts/sign.sh
# Description: Builds the Release configuration (universal, Hardened Runtime), signed with the Developer ID Application
#              identity already in the keychain, and verifies the result. Produces dist/ORIX Clean.app. Uploads nothing.
# Author: Simon-Pierre Boucher — contact@spboucher.ai
set -euo pipefail
cd "$(dirname "$0")/.."
DD="build/DerivedData"
APP="dist/ORIX Clean.app"
security find-identity -v -p codesigning | grep -q "Developer ID Application" || { echo "ERROR: no Developer ID Application identity in the keychain." >&2; exit 1; }
python3 Scripts/localize.py && xcodegen generate --quiet
rm -rf "$DD/Build/Products/Release/ORIX Clean.app"
xcodebuild -project ORIXClean.xcodeproj -scheme ORIXClean -configuration Release -derivedDataPath "$DD" build 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error:|\*\* BUILD" | sort -u
BUILT="$DD/Build/Products/Release/ORIX Clean.app"
[[ -d "$BUILT" ]] || { echo "ERROR: Release build failed." >&2; exit 1; }
rm -rf dist && mkdir -p dist
ditto "$BUILT" "$APP"
echo "== verify"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "architectures: $(lipo -archs "$APP/Contents/MacOS/ORIX Clean")"
codesign -dvv "$APP" 2>&1 | grep -E "^(Identifier|Authority|TeamIdentifier|Timestamp|Runtime Version)" | sed 's/^/  /'
FLAGS="$(codesign -dv "$APP" 2>&1 | sed -n 's/.*flags=\([^ ]*\).*/\1/p')"; echo "flags: $FLAGS"
[[ "$FLAGS" == *runtime* ]] || { echo "ERROR: Hardened Runtime is not enabled." >&2; exit 1; }
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "get-task-allow"; then echo "ERROR: get-task-allow present." >&2; exit 1; fi
echo "entitlements: $(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo '{}')"
echo "version: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist"))"
echo "RESULT: $APP is built and signed. It is NOT notarized yet (Scripts/notarize.sh)."
