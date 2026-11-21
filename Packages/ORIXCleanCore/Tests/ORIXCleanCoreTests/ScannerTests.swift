// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Packages/ORIXCleanCore/Tests/ORIXCleanCoreTests/ScannerTests.swift
// Module           : ORIXCleanCoreTests
// Repository       : https://git.spboucher.ai/orix-clean
// Created          : 2026-11-21
// Last Modified    : 2026-11-21
//
// =============================================================================
// AUTHOR & PROFESSIONAL AFFILIATION
// =============================================================================
//
// Author           : Simon-Pierre Boucher
// Position         : Professor of Finance
// Institution      : Université du Québec en Outaouais (UQO)
// Department       : Département des sciences administratives
// Organization     : SP Boucher
//
// Website          : https://spboucher.ai
// Git              : https://git.spboucher.ai
//
// =============================================================================
// OFFICIAL CONTACT DIRECTORY
// =============================================================================
//
// General          : info@spboucher.ai
// Professional     : contact@spboucher.ai
// Direct           : simon@spboucher.ai
// Research         : research@spboucher.ai
// Development      : dev@spboucher.ai
// Support          : support@spboucher.ai
// Security/Admin   : admin@spboucher.ai
// Notifications    : notifications@spboucher.ai
//
// Preferred Contact: support@spboucher.ai
//
// =============================================================================
// COPYRIGHT & INTELLECTUAL PROPERTY
// =============================================================================
//
// Copyright (c) 2026
// Simon-Pierre Boucher
//
// All rights reserved where applicable.
//
// This file is governed by the applicable project license,
// copyright notices, institutional agreements and relevant law.
//
// Unless expressly authorized by the applicable license or
// rights holder, copying, redistribution, sublicensing,
// publication and commercial exploitation are not permitted.
//
// Existing third-party rights and notices remain unaffected.
//
// =============================================================================
// CONFIDENTIALITY & SECURITY
// =============================================================================
//
// Classification   : Public
// Distribution     : Public repository; use is governed by the project license
// Security Contact : admin@spboucher.ai
//
// Access to this source does not independently grant permission
// to redistribute or disclose confidential materials.
//
// Do not embed credentials, private keys, access tokens,
// certificates or confidential personal information.
//
// =============================================================================
// LICENSE & MAINTENANCE
// =============================================================================
//
// License          : Proprietary, all rights reserved (see license file)
// License File     : LICENSE
// Maintainer       : Simon-Pierre Boucher
// Technical Contact: dev@spboucher.ai
//
// =============================================================================
// END OF SP BOUCHER SOURCE HEADER
// =============================================================================

// ORIX Clean — Packages/ORIXCleanCore/Tests/ORIXCleanCoreTests/ScannerTests.swift
// Description: Filesystem scanner tests: accounting accuracy, links, clones, sparse files, permissions, races, boundaries.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation
import Testing
@testable import ORIXCleanCore

@Suite struct ScannerTests {
    @Test func sizesMatchTheKernel() throws {
        let s = Sandbox()
        var logical: Int64 = 0, alloc: Int64 = 0
        for (i, size) in [0, 1, 4095, 4096, 4097, 70_000, 1_500_000].enumerated() {
            let p = s.file("a/b\(i % 3)/f\(i).bin", size: size, seed: UInt8(i))
            logical += Int64(size); alloc += allocated(p)
        }
        let r = try s.scan()
        #expect(r.files == 7)
        #expect(r.directories == 5)
        #expect(r.tree[0].logicalSize == logical)
        #expect(r.tree[0].allocatedSize == alloc)
        #expect(r.tree[0].fileCount == 7)
        #expect(r.issues.isEmpty)
        let du = shell("/usr/bin/du", ["-sk", s.root]).output.split(separator: "\t").first.flatMap { Int64($0) } ?? -1
        // du counts directory blocks too (0 on APFS).
        #expect(du * 1024 == alloc)
    }

    @Test func unicodeAndLongNames() throws {
        let s = Sandbox()
        let names = ["été — résumé.txt", "日本語のファイル.txt", "emoji 🧹✨.txt", "e\u{301}.txt", String(repeating: "x", count: 240) + ".txt"]
        for n in names { s.text("u/" + n, "hello") }
        let r = try s.scan()
        let found = Set(r.tree.children(of: r.tree.index(forPath: s.path("u"))!).map { r.tree.name(of: $0) })
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: s.path("u")))
        #expect(found == onDisk)
        #expect(r.tree.fileExtension(of: r.tree.index(forPath: s.path("u/" + onDisk.first!))!) == "txt")
    }

    @Test func pathsLongerThanPathMax() throws {
        let s = Sandbox()
        var rel = "deep"
        while (s.root + "/" + rel).utf8.count < 1500 { rel += "/" + String(repeating: "d", count: 200) }
        // Build with openat-relative calls because the full path is too long for mkdir.
        var fd = open(s.root, O_RDONLY)
        for part in rel.split(separator: "/") {
            mkdirat(fd, String(part), 0o755)
            let next = openat(fd, String(part), O_RDONLY)
            close(fd); fd = next
        }
        let f = openat(fd, "leaf.bin", O_CREAT | O_WRONLY, 0o644)
        write(f, "0123456789", 10)
        close(f); close(fd)
        let r = try s.scan()
        #expect(r.files == 1)
        #expect(r.tree[0].logicalSize == 10)
        #expect(r.issues.isEmpty)
        // Clean up the same way (removeItem cannot address the leaf).
        shell("/bin/rm", ["-rf", s.path("deep")])
    }

    @Test func symlinkLoopsAreNotFollowed() throws {
        let s = Sandbox()
        s.file("real/data.bin", size: 10_000)
        symlink(s.root, s.path("real/loop"))
        symlink(s.path("real"), s.path("alias"))
        symlink("/nonexistent/target", s.path("dangling"))
        let r = try s.scan()
        #expect(r.files == 1)
        #expect(r.tree[0].logicalSize >= 10_000 && r.tree[0].logicalSize < 10_000 + 4096)
        let loop = r.tree.index(forPath: s.path("real/loop"))!
        #expect(r.tree[loop].flags.contains(.symlink))
        #expect(r.tree[loop].childCount == 0)
    }

    @Test func hardLinksAreCountedOnce() throws {
        let s = Sandbox()
        let a = s.file("a.bin", size: 300_000)
        link(a, s.path("b.bin"))
        s.dir("sub"); link(a, s.path("sub/c.bin"))
        let r = try s.scan()
        #expect(r.files == 3)
        #expect(r.tree[0].logicalSize == 300_000)
        #expect(r.tree[0].allocatedSize == allocated(a))
        let dupes = r.tree.nodes.filter { $0.flags.contains(.hardLinkDuplicate) }.count
        #expect(dupes == 2)
    }

    @Test func apfsClonesReportSharedBlocks() throws {
        let s = Sandbox()
        let a = s.file("orig.bin", size: 4_000_000)
        #expect(clonefile(a, s.path("clone.bin"), 0) == 0)
        let r = try s.scan()
        #expect(r.sharingMeasured)
        let o = r.tree[r.tree.index(forPath: a)!], c = r.tree[r.tree.index(forPath: s.path("clone.bin"))!]
        #expect(o.flags.contains(.mayShareBlocks) && c.flags.contains(.mayShareBlocks))
        // Each clone reports its full allocated size, but almost nothing private: removing one frees almost nothing.
        #expect(c.allocatedSize >= 4_000_000)
        #expect(c.privateSize >= 0 && c.privateSize < 100_000)
        #expect(r.tree[0].privateSize < r.tree[0].allocatedSize / 4)
        #expect(r.tree.cloneIDs[r.tree.index(forPath: a)!] == r.tree.cloneIDs[r.tree.index(forPath: s.path("clone.bin"))!])
    }

    @Test func sparseFilesHaveSmallAllocation() throws {
        let s = Sandbox()
        let p = s.path("sparse.img")
        let fd = open(p, O_CREAT | O_WRONLY, 0o644)
        ftruncate(fd, 200_000_000)
        pwrite(fd, "end", 3, 199_999_000)
        close(fd)
        let r = try s.scan()
        let n = r.tree[r.tree.index(forPath: p)!]
        #expect(n.logicalSize == 200_000_000)
        #expect(n.allocatedSize < 1_000_000)
        #expect(n.allocatedSize == allocated(p))
    }

    @Test func permissionDeniedIsReportedAndScanContinues() throws {
        let s = Sandbox()
        s.file("open/a.bin", size: 5000)
        s.file("locked/secret.bin", size: 9000)
        chmod(s.path("locked"), 0o000)
        defer { chmod(s.path("locked"), 0o700) }
        let r = try s.scan()
        #expect(r.files == 1)
        #expect(r.issues.count == 1)
        #expect(r.issues.first?.kind == .permissionDenied)
        #expect(r.issues.first?.path == s.path("locked"))
        #expect(r.tree[r.tree.index(forPath: s.path("locked"))!].flags.contains(.unreadable))
    }

    @Test func missingAndNonDirectoryRoots() {
        let s = Sandbox()
        s.text("file.txt", "x")
        #expect(throws: ScanError.rootNotFound(s.path("nope"))) { try FileScanner(root: s.path("nope")).run() }
        #expect(throws: ScanError.rootNotDirectory(s.path("file.txt"))) { try FileScanner(root: s.path("file.txt")).run() }
    }

    @Test func filesChangingAndDisappearingDuringScan() throws {
        let s = Sandbox()
        for d in 0 ..< 60 { for f in 0 ..< 40 { s.text("churn/d\(d)/f\(f).txt", String(repeating: "x", count: f * 10)) } }
        let stop = NSLock(); nonisolated(unsafe) var running = true
        let root = s.root
        let t = Thread {
            var round = 0
            while true {
                stop.lock(); let go = running; stop.unlock()
                if !go { break }
                let d = round % 60
                try? FileManager.default.removeItem(atPath: root + "/churn/d\(d)")
                try? FileManager.default.createDirectory(atPath: root + "/churn/d\(d)", withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: root + "/churn/d\(d)/new\(round).txt", contents: Data(count: round % 500))
                round += 1
            }
        }
        t.start()
        for _ in 0 ..< 25 {
            let r = try s.scan()
            #expect(r.tree[0].logicalSize >= 0)
            #expect(r.issues.allSatisfy { $0.kind == .vanished || $0.kind == .ioError })
            var sum: Int64 = 0
            r.tree.forEachFile { _, n in sum += n.logicalSize }
            #expect(sum == r.tree[0].logicalSize)
        }
        stop.lock(); running = false; stop.unlock()
        while !t.isFinished { usleep(1000) }
    }

    @Test func largeDirectoryTree() throws {
        let s = Sandbox()
        for d in 0 ..< 200 {
            let dir = s.dir("big/d\(d)")
            for f in 0 ..< 100 { close(open(dir + "/f\(f)", O_CREAT | O_WRONLY, 0o644)) }
        }
        let big = s.dir("flat")
        for f in 0 ..< 12_000 { close(open(big + "/file-\(f).dat", O_CREAT | O_WRONLY, 0o644)) }
        let r = try s.scan()
        #expect(r.files == 32_000)
        #expect(r.directories == 203)
        #expect(r.tree[r.tree.index(forPath: big)!].childCount == 12_000)
    }

    @Test func packagesAreFlagged() throws {
        let s = Sandbox()
        s.file("Demo.app/Contents/MacOS/Demo", size: 50_000)
        s.file("Lib.photoslibrary/database/Photos.sqlite", size: 20_000)
        s.file("plain/file.bin", size: 30_000)
        let r = try s.scan()
        #expect(r.tree[r.tree.index(forPath: s.path("Demo.app"))!].flags.contains(.package))
        #expect(r.tree[r.tree.index(forPath: s.path("Lib.photoslibrary"))!].flags.contains(.package))
        #expect(!r.tree[r.tree.index(forPath: s.path("plain"))!].flags.contains(.package))
        let hits = TreeQuery.largestFiles(in: r.tree)
        #expect(hits.map { r.tree.name(of: $0.node) } == ["file.bin"])
        var f = FileFilter(); f.includePackageContents = true
        #expect(TreeQuery.largestFiles(in: r.tree, filter: f).count == 3)
    }

    @Test func cancellationAndPause() throws {
        let s = Sandbox()
        for d in 0 ..< 50 { s.text("c/d\(d)/f.txt", "x") }
        let scanner = FileScanner(root: s.root)
        scanner.cancel()
        let r = try scanner.run()
        #expect(r.cancelled)
        #expect(r.files < 50)

        let paused = FileScanner(root: s.root)
        paused.pause()
        nonisolated(unsafe) var result: ScanResult?
        let t = Thread { result = try? paused.run() }
        t.start()
        usleep(200_000)
        #expect(result == nil)
        #expect(paused.isPaused)
        #expect(paused.progress.files == 0)
        paused.resume()
        while !t.isFinished { usleep(1000) }
        #expect(result?.files == 50)
        #expect(result?.cancelled == false)
    }

    @Test func excludedPathsAndRemoval() throws {
        let s = Sandbox()
        s.file("keep/a.bin", size: 10_000)
        s.file("skip/b.bin", size: 20_000)
        s.file("keep/sub/c.bin", size: 30_000)
        var o = ScanOptions(); o.excludedPaths = [s.path("skip")]
        let r = try s.scan(options: o)
        #expect(r.files == 2)
        #expect(r.tree[r.tree.index(forPath: s.path("skip"))!].flags.contains(.skipped))
        let sub = r.tree.index(forPath: s.path("keep/sub"))!
        let before = r.tree[0]
        r.tree.markRemoved(sub)
        #expect(r.tree[0].logicalSize == before.logicalSize - 30_000)
        #expect(r.tree[0].fileCount == 1)
        #expect(r.tree.sortedChildren(of: r.tree.index(forPath: s.path("keep"))!).count == 1)
        #expect(TreeQuery.largestFiles(in: r.tree).count == 1)
    }

    @Test func mountedVolumeIsABoundaryAndRemovalIsAnError() throws {
        let s = Sandbox()
        s.file("local.bin", size: 10_000)
        let mount = s.dir("mnt")
        guard let v = TestVolume(mountAt: mount) else { Issue.record("hdiutil unavailable"); return }
        FileManager.default.createFile(atPath: mount + "/onvolume.bin", contents: Data(count: 500_000))
        let r = try s.scan()
        #expect(r.files == 1)
        #expect(r.tree[r.tree.index(forPath: mount)!].flags.contains(.boundary))
        var o = ScanOptions(); o.stayOnDevice = false
        #expect(try s.scan(options: o).files >= 2)
        // Scanning the volume itself works; after it is ejected the mount point is an empty local directory.
        #expect(try FileScanner(root: mount).run().tree[0].logicalSize >= 500_000)
        v.detach()
        #expect(try FileScanner(root: mount).run().files == 0)
    }

    @Test func queriesAndCategories() throws {
        let s = Sandbox()
        s.file("m/movie.mp4", size: 900_000)
        s.file("m/song.mp3", size: 300_000)
        s.file("m/old.zip", size: 600_000)
        s.file("m/pic.JPG", size: 100_000)
        var times = [timeval(tv_sec: 1_500_000_000, tv_usec: 0), timeval(tv_sec: 1_500_000_000, tv_usec: 0)]
        utimes(s.path("m/old.zip"), &times)
        let r = try s.scan()
        #expect(TreeQuery.largestFiles(in: r.tree, limit: 2).map { r.tree.name(of: $0.node) } == ["movie.mp4", "old.zip"])
        var f = FileFilter(); f.categories = [.archive]
        #expect(TreeQuery.largestFiles(in: r.tree, filter: f).count == 1)
        f = FileFilter(); f.modifiedBefore = Date(timeIntervalSince1970: 1_600_000_000)
        #expect(TreeQuery.largestFiles(in: r.tree, filter: f).map { r.tree.name(of: $0.node) } == ["old.zip"])
        f = FileFilter(); f.nameContains = "PIC"
        #expect(TreeQuery.largestFiles(in: r.tree, filter: f).count == 1)
        f = FileFilter(); f.minimumSize = 500_000; f.sizeKind = .logical
        #expect(TreeQuery.largestFiles(in: r.tree, filter: f).count == 2)
        let cats = Dictionary(uniqueKeysWithValues: TreeQuery.categories(in: r.tree).map { ($0.category, $0.logical) })
        #expect(cats[.video] == 900_000 && cats[.audio] == 300_000 && cats[.archive] == 600_000 && cats[.image] == 100_000)
        #expect(TreeQuery.largestFolders(in: r.tree).first.map { r.tree.name(of: $0.node) } == "m")
        let m = Measure.item(s.path("m"))!
        #expect(m.logical == 1_900_000 && m.files == 4 && m.isDirectory)
        #expect(Volumes.containing(s.root) != nil)
        #expect(Volumes.mounted().contains { $0.isStartup })
    }
}

@Suite struct TreemapTests {
    @Test func areasAreProportionalAndInsideTheParent() throws {
        let s = Sandbox()
        s.file("a/big.bin", size: 4_000_000); s.file("a/mid.bin", size: 2_000_000); s.file("b/small.bin", size: 1_000_000)
        for i in 0 ..< 50 { s.file("b/tiny\(i).bin", size: 300) }
        let tree = try s.scan().tree
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        var o = TreemapOptions(); o.padding = 0; o.header = 0; o.sizeKind = .logical; o.minimumArea = 40
        let cells = Treemap.layout(tree: tree, root: 0, in: rect, options: o)
        #expect(cells.allSatisfy { rect.insetBy(dx: -0.01, dy: -0.01).contains($0.rect) })
        let leaves = cells.filter { $0.isLeaf && $0.aggregateCount == 0 }
        let big = leaves.first { tree.name(of: $0.node) == "big.bin" }!, mid = leaves.first { tree.name(of: $0.node) == "mid.bin" }!
        let ratio = (big.rect.width * big.rect.height) / (mid.rect.width * mid.rect.height)
        #expect(abs(ratio - 2) < 0.01)
        let total = Double(tree[0].logicalSize)
        #expect(abs(Double(big.rect.width * big.rect.height) / Double(rect.width * rect.height) - 4_000_000 / total) < 0.001)
        // The 50 tiny files are merged into one honest aggregate cell.
        let aggregate = cells.first { $0.aggregateCount > 0 }
        #expect(aggregate?.aggregateCount == 50 && aggregate?.aggregateSize == 15_000)
        // Leaves do not overlap.
        for i in leaves.indices { for j in leaves.indices where j > i {
            let x = leaves[i].rect.intersection(leaves[j].rect)
            #expect(x.isNull || x.width * x.height < 0.5)
        } }
        #expect(Treemap.squarify(areas: [], in: rect).isEmpty)
        var culled = o; culled.visible = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(Treemap.layout(tree: tree, root: 0, in: rect, options: culled).count < cells.count)
    }
}
