#!/usr/bin/env bash
# ORIX Clean — Scripts/shot.sh
# Description: Launches an isolated instance on the sample home folder and captures its window (by window id).
#   Scripts/shot.sh <out.png> <section> [dark|light] [extra app args…]
# Author: Simon-Pierre Boucher — contact@spboucher.ai
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; SECTION="$2"; LOOK="${3:-dark}"; shift 3 || shift $#
APP="${ORIX_APP:-build/DerivedData/Build/Products/Debug/ORIX Clean.app}"
HOME_DIR="${ORIX_DEMO_HOME:-/tmp/orix-demo/home}"
WAIT="${ORIX_WAIT:-5}"
"$APP/Contents/MacOS/ORIX Clean" -ORIXHome "$HOME_DIR" -ORIXStore "${ORIX_STORE:-memory}" -ORIXScanRoot "$HOME_DIR" -ORIXSection "$SECTION" \
  -ORIXAppearance "$LOOK" -ORIXSkipOnboarding YES -ORIXAutoAnalyze YES -ApplePersistenceIgnoreState YES "$@" >/dev/null 2>&1 &
PID=$!
sleep "$WAIT"
WID=$(swift - "$PID" <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
if ProcessInfo.processInfo.environment["ORIX_FRONT"] != nil {
    // Frontmost window of the instance (a sheet or the Settings window); the list is ordered front to back.
    for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
        print(w[kCGWindowNumber as String] as? Int ?? 0); exit(0)
    }
}
var best = (0, 0.0)
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    if area > best.1 { best = (w[kCGWindowNumber as String] as? Int ?? 0, area) }
}
print(best.0)
SWIFT
)
if [[ -n "${ORIX_HOOK:-}" ]]; then eval "$ORIX_HOOK"; fi
mkdir -p "$(dirname "$OUT")"
screencapture -x -o -l "$WID" "$OUT"
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
echo "$OUT"
