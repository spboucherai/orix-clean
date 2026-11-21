#!/usr/bin/env bash
# =============================================================================
#                  SP BOUCHER | INFRASTRUCTURE & AUTOMATION
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# Project          : ORIX Clean
# File             : Scripts/finalize.sh
# Description      : After the DMG is notarized and stapled: verifies
#                    Gatekeeper on app, DMG and ZIP content, writes SHA-256
#                    checksums and dist/release.json with measured values only.
# Module           : Scripts
# Repository       : https://git.spboucher.ai/orix-clean
# Created          : 2026-11-21
# Last Modified    : 2026-11-21
#
# Author           : Simon-Pierre Boucher
# Position         : Professor of Finance
# Institution      : Université du Québec en Outaouais (UQO)
# Organization     : SP Boucher
# Website          : https://spboucher.ai
# Git              : https://git.spboucher.ai
#
# Preferred Contact: support@spboucher.ai
# Technical Contact: dev@spboucher.ai
# Security/Admin   : admin@spboucher.ai
#
# Copyright (c) 2026
# Simon-Pierre Boucher
# All rights reserved where applicable. This file is governed by the
# applicable project license, copyright notices and relevant law.
# Existing third-party rights and notices remain unaffected.
#
# License          : Proprietary, all rights reserved (see license file)
# License File     : LICENSE
#
# Do not embed credentials, private keys, access tokens,
# certificates or confidential personal information.
#
# =============================================================================
# END OF SP BOUCHER SOURCE HEADER
# =============================================================================

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
        "notarization": {k: {"submission": i, "status": json.load(open(f"build/notary/{k}.json")).get("status", "unknown") if i else "unknown"} for k, i in (("app", appid), ("dmg", dmgid))},
        "artifacts": [{"file": os.path.basename(p), "bytes": os.path.getsize(p), "sha256": sha(p)} for p in (dmg, zp)]}
json.dump(meta, open("dist/release.json", "w"), indent=1)
print(json.dumps(meta, indent=1))
PY
