#!/usr/bin/env bash
# ORIX Clean — Scripts/finalize.sh
# Description: After the DMG is notarized and stapled: verifies Gatekeeper on app, DMG and ZIP content, writes SHA-256
#              checksums and dist/release.json with measured values only.
# Author: Simon-Pierre Boucher — contact@spboucher.ai
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/ORIX Clean.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
MIN="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
DMG="dist/ORIXClean-$VERSION.dmg"; ZIP="dist/ORIXClean-$VERSION.zip"
echo "== Gatekeeper"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" 2>&1 | sed 's/^/  /'
xcrun stapler validate "$APP"; xcrun stapler validate "$DMG"
T="$(mktemp -d)"; ditto -x -k "$ZIP" "$T"; spctl --assess --type execute --verbose=2 "$T/ORIX Clean.app" 2>&1 | sed 's/^/  zip: /'; xcrun stapler validate "$T/ORIX Clean.app" | sed 's/^/  zip: /'; rm -rf "$T"
(cd dist && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" | tee SHA256SUMS.txt)
APPID="$(/usr/bin/python3 -c 'import json;print(json.load(open("build/notary/app.json"))["id"])' 2>/dev/null || echo "")"
DMGID="$(/usr/bin/python3 -c 'import json;print(json.load(open("build/notary/dmg.json"))["id"])' 2>/dev/null || echo "")"
/usr/bin/python3 - "$VERSION" "$BUILD" "$MIN" "$DMG" "$ZIP" "$APPID" "$DMGID" "$(lipo -archs "$APP/Contents/MacOS/ORIX Clean")" <<'PY'
import json, os, sys, hashlib
v, b, m, dmg, zp, appid, dmgid, archs = sys.argv[1:]
def sha(p): return hashlib.sha256(open(p, 'rb').read()).hexdigest()
meta = {"name": "ORIX Clean", "bundleIdentifier": "ai.spboucher.orix.clean", "version": v, "build": b, "minimumMacOS": m,
        "architectures": archs.split(), "signing": "Developer ID Application, Hardened Runtime",
        "notarization": {"app": {"submission": appid, "status": "Accepted"}, "dmg": {"submission": dmgid, "status": "Accepted"}},
        "artifacts": [{"file": os.path.basename(p), "bytes": os.path.getsize(p), "sha256": sha(p)} for p in (dmg, zp)]}
json.dump(meta, open("dist/release.json", "w"), indent=1)
print(json.dumps(meta, indent=1))
PY
