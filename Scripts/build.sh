#!/usr/bin/env bash
# ORIX Clean — Scripts/build.sh
# Description: Developer entry point. generate | debug | core-test | uitest | run | all
# Author: Simon-Pierre Boucher — contact@spboucher.ai
set -euo pipefail
cd "$(dirname "$0")/.."
DD="build/DerivedData"
filter() { sed 's/\x1b\[[0-9;]*m//g' | grep -E "error:|warning: unused|\*\* (BUILD|TEST)|Executed|Test Case.*failed|✘|Test run" | sort -u || true; }
case "${1:-all}" in
  generate) [[ -f Scripts/translations-fr.json ]] && python3 Scripts/localize.py >/dev/null; xcodegen generate --quiet ;;
  debug) "$0" generate; xcodebuild -project ORIXClean.xcodeproj -scheme ORIXClean -configuration Debug -derivedDataPath "$DD" build 2>&1 | filter ;;
  core-test) (cd Packages/ORIXCleanCore && swift test 2>&1 | filter) ;;
  uitest) "$0" generate
          # The sample home lives on a disposable disk image so that cleanup tests use that image's own Trash.
          hdiutil detach /tmp/orix-uitest -force -quiet 2>/dev/null || true
          rm -rf /tmp/orix-uitest /tmp/orix-uitest.dmg; mkdir -p /tmp/orix-uitest
          hdiutil create -size 900m -fs APFS -volname ORIXUITest -quiet /tmp/orix-uitest.dmg
          hdiutil attach /tmp/orix-uitest.dmg -nobrowse -mountpoint /tmp/orix-uitest -quiet -owners on
          (cd Packages/ORIXCleanCore && swift build -c release 2>&1 | grep -E "error" || true)
          Packages/ORIXCleanCore/.build/release/orix-bench fixture /tmp/orix-uitest/home 0.25 >/dev/null
          xcodebuild -project ORIXClean.xcodeproj -scheme ORIXClean -configuration Debug -derivedDataPath "$DD" test ${ORIX_ONLY:+-only-testing:ORIXCleanUITests/ORIXCleanUITests/$ORIX_ONLY} 2>&1 | tee build/uitest.log | filter
          hdiutil detach /tmp/orix-uitest -force -quiet || true; rm -f /tmp/orix-uitest.dmg ;;
  run) open "$DD/Build/Products/Debug/ORIX Clean.app" ;;
  all) "$0" core-test; "$0" debug ;;
  *) echo "usage: $0 generate|debug|core-test|uitest|run|all"; exit 2 ;;
esac
