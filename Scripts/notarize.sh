#!/usr/bin/env bash
# =============================================================================
#                  SP BOUCHER | INFRASTRUCTURE & AUTOMATION
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# Project          : ORIX Clean
# File             : Scripts/notarize.sh
# Description      : Notarizes dist/ORIX Clean.app with an EXISTING notarytool
#                    keychain profile and staples the ticket. NOTARY_PROFILE
#                    defaults to MacLustr-Notarize. Never creates, prints or
#                    changes credentials. The word "notarized" is printed only
#                    when Apple's service answered Accepted.
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
PROFILE="${NOTARY_PROFILE:-MacLustr-Notarize}"
TARGET="${1:-dist/ORIX Clean.app}"
NAME="${2:-app}"
[[ -e "$TARGET" ]] || { echo "ERROR: $TARGET not found. Run Scripts/sign.sh first." >&2; exit 1; }
mkdir -p build/notary
SUBMIT="$TARGET"
if [[ -d "$TARGET" ]]; then SUBMIT="build/notary/$NAME.zip"; rm -f "$SUBMIT"; ditto -c -k --keepParent "$TARGET" "$SUBMIT"; fi
OUT="build/notary/$NAME.json"
if ! xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait --output-format json >"$OUT" 2>"$OUT.err"; then
  echo "Notary service refused the submission:" >&2; head -8 "$OUT.err" >&2; exit 2
fi
STATUS="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$OUT")"
ID="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$OUT")"
echo "submission $ID: $STATUS"
xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "build/notary/$NAME-log.json" >/dev/null 2>&1 || true
[[ "$STATUS" == "Accepted" ]] || { echo "RESULT: NOT notarized. See build/notary/$NAME-log.json" >&2; exit 3; }
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "RESULT: $TARGET is notarized by Apple (submission $ID) and stapled."
