// ORIX Clean — Packages/ORIXCleanCore/Sources/orix-bench/main.swift
// Description: Command-line benchmark and accuracy probe for the core engines.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation
import ORIXCleanCore

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "help"

func rss() -> Int64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
    return kr == KERN_SUCCESS ? Int64(info.resident_size) : 0
}

func cpuSeconds() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6 + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
}

switch command {
case "scan":
    // orix-bench scan <path> [workers]
    let path = args.count > 2 ? args[2] : NSHomeDirectory()
    var o = path == "/" ? ScanOptions.startupVolume() : ScanOptions()
    if args.count > 3 { o.workers = Int(args[3]) ?? 0 }
    let cpu0 = cpuSeconds()
    let r = try FileScanner(root: path, options: o).run()
    let cpu = cpuSeconds() - cpu0
    print("path=\(path) files=\(r.files) dirs=\(r.directories) issues=\(r.issues.count) seconds=\(String(format: "%.3f", r.duration)) objects_per_s=\(Int(r.filesPerSecond)) cpu_s=\(String(format: "%.2f", cpu)) rss_mb=\(rss() / 1_048_576) bytes_per_object=\(rss() / Int64(max(1, r.tree.count)))")
    print("logical=\(r.tree[0].logicalSize) allocated=\(r.tree[0].allocatedSize) private=\(r.tree[0].privateSize) sharing=\(r.sharingMeasured)")
case "dupes":
    let path = args.count > 2 ? args[2] : NSHomeDirectory()
    let r = try FileScanner(root: path).run()
    var o = DuplicateOptions()
    o.minimumSize = args.count > 3 ? Int64(args[3]) ?? 1 : 1
    let d = DuplicateFinder().run(tree: r.tree, options: o)
    print("candidates=\(d.candidates) groups=\(d.groups.count) hashed_bytes=\(d.bytesHashed) seconds=\(String(format: "%.3f", d.duration)) mb_per_s=\(Int(Double(d.bytesHashed) / 1e6 / max(d.duration, 0.001))) redundant=\(d.redundantLogical) rss_mb=\(rss() / 1_048_576)")
case "similar":
    let path = args.count > 2 ? args[2] : NSHomeDirectory()
    let r = try FileScanner(root: path).run()
    let s = SimilarImageFinder().run(tree: r.tree)
    print("images=\(s.imagesExamined) groups=\(s.groups.count) unreadable=\(s.unreadable) seconds=\(String(format: "%.3f", s.duration)) images_per_s=\(Int(Double(s.imagesExamined) / max(s.duration, 0.001)))")
case "treemap":
    let path = args.count > 2 ? args[2] : NSHomeDirectory()
    let r = try FileScanner(root: path).run()
    let t0 = Date()
    var cells = 0
    for _ in 0 ..< 100 { cells = Treemap.layout(tree: r.tree, root: 0, in: CGRect(x: 0, y: 0, width: 1600, height: 1000)).count }
    print("nodes=\(r.tree.count) cells=\(cells) layout_ms=\(String(format: "%.3f", Date().timeIntervalSince(t0) * 10))")
case "sample":
    // orix-bench sample <db> [interval seconds]: records real volume samples until killed.
    let store = try HistoryStore(path: args[2])
    let interval = args.count > 3 ? Double(args[3]) ?? 300 : 300
    while true {
        for v in Volumes.mounted() where v.isStartup { store.record(volume: v, minimumInterval: 0) }
        Thread.sleep(forTimeInterval: interval)
    }
case "fixture":
    // orix-bench fixture <dir> [scale]: writes a sample home folder with real files.
    Fixture.build(home: args[2], scale: args.count > 3 ? Double(args[3]) ?? 1 : 1)
    print("fixture written to \(args[2])")
default:
    print("usage: orix-bench scan|dupes|similar|treemap|sample|fixture <path> …")
}
