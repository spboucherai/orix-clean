#!/usr/bin/env bash
# =============================================================================
#                  SP BOUCHER | INFRASTRUCTURE & AUTOMATION
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# Project          : ORIX Clean
# File             : Scripts/package.sh
# Description      : Builds the distribution artifacts from the notarized,
#                    stapled dist/ORIX Clean.app: a signed DMG (background
#                    artwork, Applications shortcut), a ZIP, SHA-256 checksums
#                    and release metadata. The DMG must then be notarized:
#                    Scripts/notarize.sh dist/ORIXClean-<version>.dmg dmg
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
echo "built $DMG and $ZIP (version $VERSION build $BUILD). Notarize the DMG next, then run: Scripts/finalize.sh"
