<!-- ORIX Clean / File: docs/release/RELEASE_NOTES.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# ORIX Clean 1.0.0

First release. A native macOS storage analyzer and cleanup utility. No account, no network access, nothing removed without your confirmation.

## What it does

- **Storage analysis** of any folder or volume: content size, size on disk, and the space APFS reports as private to each file.
- **Interactive storage map** (treemap): drill down, zoom, pan, search, with a list beside it.
- **Large files and folders** with filters by size, age, type and name.
- **Exact duplicates**: size, sampled hash, full SHA-256, then a byte-for-byte check before a copy is removed. Hard links and APFS clones are recognised.
- **Similar images**, computed on the Mac with Vision. Nothing is preselected.
- **Caches & logs**, **developer data**, **downloads** and **Trash**, each item with its reason, risk and consequence.
- **Uninstall assistant** and **leftover detection**, with the certainty of every association stated.
- **Cleanup preview** before every removal; items go to the Trash and can be put back.
- **History**, **Actions** (reusable workflows) and **reports** (PDF, CSV, JSON, Markdown).
- English and Canadian French.

## Requirements

- macOS 15.0 or later (built and tested on macOS 27.0 only).
- Apple Silicon or Intel (universal binary; the Intel slice has not been run).

## Install

Open the disk image and drag **ORIX Clean** to **Applications**. Full Disk Access is optional (System Settings > Privacy & Security > Full Disk Access); without it, protected folders are not read and the app says so.

## Known limitations

See `README.md` (Known Limitations) and `RELEASE-REPORT.md`.
