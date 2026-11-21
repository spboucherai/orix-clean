<!-- ORIX Clean / File: docs/development/performance.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Performance

Measurements of the core engines, how they were taken, how to repeat them, and what was not measured. Every
figure in this document was measured; the one estimate is labelled as such.

## Environment

| Item | Value |
|---|---|
| Date | 2026-11-21 |
| Machine | MacBook Pro `Mac17,6`, Apple M5 Max, 18 cores, 48 GB |
| System | macOS 27.0 (26A5425a) |
| Storage | Internal APFS SSD |
| Toolchain | Xcode 27.2, Swift 6.4.2 |
| Binary | `orix-bench`, release build |
| Cache state | Warm file cache (each tree had been read before the timed run) |

## Methodology

- All figures come from `orix-bench`, which calls the same `ORIXCleanCore` engines as the application.
- **Duration** is `ScanResult.duration` (wall clock, from the start of traversal to the end of aggregation) or
  the corresponding `duration` of the duplicate and similar-image results.
- **CPU seconds** are user plus system time from `getrusage(RUSAGE_SELF)` around the scan.
- **RSS** is `resident_size` from `task_info(MACH_TASK_BASIC_INFO)` read after the scan, with the tree still in
  memory. It includes the whole process, not only the tree.
- **Objects** are files plus folders. Throughput is objects divided by duration.
- **Treemap** time is the average of 100 consecutive layouts of the same tree.
- Each figure is from the runs reported here; no statistical treatment (variance, confidence interval) was
  done. Treat differences of a few percent as noise.
- Warm cache means metadata and file contents were already in memory. A first scan after boot, and any hashing
  of files that are not cached, will be slower and bound by the storage device.

## Scan

| Tree | Files | Folders | Threads | Duration | Throughput | Peak RSS |
|---|---|---|---|---|---|---|
| `~/Library/Developer` | 985,558 | 699,525 | 8 | 17.4 s | 96,757 objects/s | 202 MB (about 125 bytes per object) |
| `/Applications` | 448,727 | 64,278 | see below | 2.92 to 4.07 s | | about 77 MB |
| `/System/Library` | 296,089 | 159,923 | not recorded | 3.27 s | | |

The `/System/Library` scan reported 68 unreadable folders; they are listed as issues and excluded from totals.

Accuracy: on a tree of about 31,000 objects the allocated total reported by the scanner matched `du -sk`
exactly. The same equality is asserted on a small tree by the test `sizesMatchTheKernel`.

### Thread count

`/Applications`, same tree, warm cache:

| Threads | Wall time | CPU time |
|---|---|---|
| 1 | 3.45 s | 3.4 s |
| 2 | 3.49 s | 6.8 s |
| 3 | 3.04 s | 8.9 s |
| 4 | 2.92 s | 11.2 s |
| 6 | 2.96 s | 16.7 s |
| 8 | 4.07 s | 23.4 s |

Reading the table:

- Wall time barely moves: the best run (4 threads, 2.92 s) is 15 % faster than one thread.
- CPU time grows almost linearly with the thread count: eight threads use about seven times the CPU of one
  and are slower than one in wall time.
- Directory enumeration is bound by the filesystem, not by the number of cores. Batches are also committed
  to the tree under a single lock, which is consistent with the flat wall time; lock contention was not
  profiled.

**Decision: the default is 3 threads.** Three threads reach about 96 % of the best measured throughput
(2.92 / 3.04) for 38 % of the CPU time of eight (8.9 / 23.4). The default drops to 1 thread when the thermal
state is serious or critical, or when Low Power Mode is on (`FileScanner.run`). `ScanOptions.workers` overrides
it; `Measure.item` uses 2 for the small directory measurements made while listing candidates.

The `~/Library/Developer` figure above was taken with 8 threads; that tree was not measured again with 3.

## Memory model

Scan results live in memory only. The tree costs:

| Part | Cost |
|---|---|
| `ScanNode` | 64 bytes per object, in one contiguous array |
| Names | UTF-8 bytes of each name, back to back, no terminator |
| Clone ids | one dictionary entry per file that may share blocks |
| Transient | hard-link and directory "seen" sets during the scan, one 256 KiB buffer per thread, array growth slack |

Measured: 202 MB resident for 1,685,083 objects, about 125 bytes per object for the whole process.

**Estimate, not a measurement:** a scan of the whole startup volume of the test machine (about 15 million
inodes) at 125 to 160 bytes per object would need roughly 1.9 to 2.4 GB. This was not run. The per-object range
extrapolates from one measured tree; a volume with longer names or many hard links may fall outside it.

Hard limits in the data structure: node indexes are `Int32` and name offsets are `UInt32`, so a tree is limited
to about 2.1 billion objects and 4 GiB of names. Past either limit the scanner records an issue and drops the
directory rather than overflowing.

## Treemap

| Tree | Viewport | Cells produced | Layout time |
|---|---|---|---|
| 467,907 nodes | 1600 by 1000 | 1,798 | 0.162 ms (average of 100 runs) |

The layout visits only folders whose rectangle is large enough to open and merges invisible children into one
cell, so its cost follows what is visible, not the size of the tree. This measurement is the reason the map is
drawn with SwiftUI `Canvas` and no Metal renderer was written. Drawing time (text and gradients for the cells)
was not measured separately.

## Duplicate hashing

| Input | Data hashed | Duration | Threads | Cache |
|---|---|---|---|---|
| Sample folder, scale 1 | 685 MB | 0.069 s | 6 | warm |

**This is a warm-cache figure.** The sample files had just been written and were served from memory. It shows
that SHA-256 (CryptoKit) is not the bottleneck on this processor; it says nothing about cold reads. On cold
data, hashing speed is bound by the read throughput of the disk, and the engine sets `F_NOCACHE` so that a
large run does not displace other cached data. No cold-cache run was measured.

## Similar images

| Input | Images | Duration | Mode |
|---|---|---|---|
| Sample folder, scale 1 | 31 | 0.21 s (about 150 images/s) | fast |

Fast mode computes a thumbnail and a 64-bit hash per image and runs Vision only for pairs whose hashes are
close. Thorough mode (Vision for every image and every pair) was not timed. Pair comparison is quadratic in
the number of images.

## Sample folder

`orix-bench fixture <dir>` at scale 1 writes 182 files totalling 1.89 GB. UI tests use scale 0.25.

## Reproducing

```sh
cd Packages/ORIXCleanCore
swift build -c release
B=.build/release/orix-bench

$B scan ~/Library/Developer 8        # path, optional thread count (0 or omitted = default)
for n in 1 2 3 4 6 8; do $B scan /Applications $n; done
$B scan /System/Library
$B treemap /Applications             # average layout time over 100 runs at 1600 by 1000
$B fixture /tmp/orix-demo/home       # deletes and rewrites the target directory
$B dupes /tmp/orix-demo/home         # optional minimum size in bytes as a third argument
$B similar /tmp/orix-demo/home
```

Run each command twice and keep the second result to match the warm-cache condition.

| Command | Output fields |
|---|---|
| `scan` | `files`, `dirs`, `issues`, `seconds`, `objects_per_s`, `cpu_s`, `rss_mb`, `bytes_per_object`, then `logical`, `allocated`, `private`, `sharing` |
| `dupes` | `candidates`, `groups`, `hashed_bytes`, `seconds`, `mb_per_s`, `redundant`, `rss_mb` |
| `similar` | `images`, `groups`, `unreadable`, `seconds`, `images_per_s` |
| `treemap` | `nodes`, `cells`, `layout_ms` |
| `sample <db> [interval]` | records real startup-volume samples into a history database until stopped |
| `fixture <dir> [scale]` | writes the sample folder |

`scan /` uses `ScanOptions.startupVolume()`, as the application does.

## Not measured

- **Intel Macs.** The Release build is universal, but the `x86_64` slice was not run.
- **macOS 15 and macOS 26.** The application is built for 15.0 and later and was run on 27.0 only.
- **External, HDD and network volumes.** Nothing beyond a small APFS disk image was exercised. Seek-bound and
  latency-bound storage may favour a different thread count.
- **Cold-cache scans and cold-cache hashing.**
- **A full-disk scan of the test machine**, in time or memory (see the estimate above).
- **Battery impact** and energy use.
- **Interface responsiveness**: frame times of the map, list scrolling with large results, memory of the
  application process as opposed to `orix-bench`.
- **VoiceOver with a real user** (see `docs/ACCESSIBILITY.md`).
- **Thorough image mode**, and image libraries larger than the sample.
