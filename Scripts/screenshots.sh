#!/usr/bin/env bash
# =============================================================================
#                  SP BOUCHER | INFRASTRUCTURE & AUTOMATION
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# Project          : ORIX Clean
# File             : Scripts/screenshots.sh
# Description      : Captures the README screenshots from the real app (Debug
#                    build) running on the generated sample home folder. The
#                    sample lives on a disposable disk image, so the cleanup
#                    shown in the "results" screenshot uses that image's Trash.
#                    History screenshots use real volume samples of this Mac
#                    from ORIX_HISTORY_DB when given.
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
OUT="docs/screenshots"; MNT=/tmp/orix-demo; IMG=/tmp/orix-demo.sparseimage
EN=(-AppleLanguages "(en)" -AppleLocale en_CA); FR=(-AppleLanguages "(fr-CA)" -AppleLocale fr_CA)
hdiutil detach "$MNT" -force -quiet 2>/dev/null || true
rm -rf "$MNT" "$IMG"; mkdir -p "$MNT" "$OUT"
hdiutil create -size 4g -type SPARSE -fs APFS -volname "ORIX Sample" -quiet "${IMG%.sparseimage}"
hdiutil attach "$IMG" -nobrowse -mountpoint "$MNT" -quiet -owners on
Packages/ORIXCleanCore/.build/release/orix-bench fixture "$MNT/home" 1 >/dev/null
export ORIX_DEMO_HOME="$MNT/home"
HIST=memory
if [[ -n "${ORIX_HISTORY_DB:-}" && -f "$ORIX_HISTORY_DB" ]]; then rm -f /tmp/orix-shot-history.sqlite*; sqlite3 "$ORIX_HISTORY_DB" ".backup /tmp/orix-shot-history.sqlite"; HIST=/tmp/orix-shot-history.sqlite; fi
shot() { local name="$1" section="$2" look="$3"; shift 3; Scripts/shot.sh "$OUT/$name.png" "$section" "$look" "$@" >/dev/null && echo "$name"; }
ORIX_WAIT=7 shot 01-overview overview dark "${EN[@]}"
ORIX_WAIT=6 shot 02-storage-map map dark "${EN[@]}"
ORIX_WAIT=6 shot 03-large-files largeFiles dark "${EN[@]}"
ORIX_WAIT=8 shot 04-duplicates duplicates dark "${EN[@]}" -ORIXDemoSelect duplicates
ORIX_WAIT=8 shot 05-similar-images similar dark "${EN[@]}"
ORIX_WAIT=7 shot 06-cache-cleanup caches dark "${EN[@]}" -ORIXDemoSelect caches
ORIX_WAIT=8 shot 07-uninstall-assistant applications dark "${EN[@]}" -ORIXDemoSelect uninstall
ORIX_WAIT=7 shot 08-developer-cleanup developer dark "${EN[@]}"
ORIX_WAIT=8 ORIX_FRONT=1 shot 09-cleanup-preview caches dark "${EN[@]}" -ORIXDemoSelect caches -ORIXDemoPreview YES
ORIX_WAIT=7 shot 12-reports reports dark "${EN[@]}"
ORIX_WAIT=6 shot 16-downloads downloads dark "${EN[@]}"
ORIX_WAIT=6 shot 17-trash trash dark "${EN[@]}"
ORIX_WAIT=6 shot 18-actions actions dark "${EN[@]}"
ORIX_WAIT=6 ORIX_FRONT=1 shot 13-settings overview dark "${EN[@]}" -ORIXOpenSettings YES
ORIX_WAIT=7 shot 14-light-mode overview light "${EN[@]}"
ORIX_WAIT=6 shot 15-storage-map-light map light "${EN[@]}"
ORIX_WAIT=7 shot 19-french-canadian map dark "${FR[@]}"
ORIX_STORE="$HIST" ORIX_WAIT=6 shot 11-storage-history history dark "${EN[@]}"
# Last: a real cleanup of the sample caches (moves them to the Trash of the sample disk image).
ORIX_WAIT=9 ORIX_FRONT=1 shot 10-cleanup-results caches dark "${EN[@]}" -ORIXDemoSelect caches -ORIXDemoConfirm YES
hdiutil detach "$MNT" -force -quiet || true; rm -f "$IMG" /tmp/orix-shot-history.sqlite*
ls "$OUT" | wc -l
