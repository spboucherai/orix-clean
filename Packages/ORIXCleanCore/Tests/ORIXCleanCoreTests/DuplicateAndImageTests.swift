// ORIX Clean — Packages/ORIXCleanCore/Tests/ORIXCleanCoreTests/DuplicateAndImageTests.swift
// Description: Duplicate detection and similar-image tests on generated files.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ORIXCleanCore

@Suite struct DuplicateTests {
    @Test func exactDuplicatesAreGroupedAndDifferentFilesAreNot() throws {
        let s = Sandbox()
        s.file("a/one.bin", size: 200_000, seed: 1)
        s.file("b/one-copy.bin", size: 200_000, seed: 1)
        s.file("c/one-third.bin", size: 200_000, seed: 1)
        s.file("a/same-size-different.bin", size: 200_000, seed: 2)
        s.file("a/small.bin", size: 10, seed: 3)
        s.file("b/small.bin", size: 10, seed: 3)
        s.file("a/unique.bin", size: 12_345, seed: 4)
        let r = DuplicateFinder().run(tree: try s.scan().tree)
        #expect(r.groups.count == 2)
        #expect(r.groups[0].files.count == 3 && r.groups[0].logicalSize == 200_000)
        #expect(r.groups[0].redundantLogical == 400_000)
        #expect(r.groups[1].files.count == 2 && r.groups[1].logicalSize == 10)
        #expect(r.redundantLogical == 400_010)
        #expect(!r.groups[0].sharesStorage)
        let expected = shell("/usr/bin/shasum", ["-a", "256", s.path("a/one.bin")]).output.split(separator: " ").first.map(String.init)
        #expect(r.groups[0].digest == expected)
        var o = DuplicateOptions(); o.minimumSize = 1000
        #expect(DuplicateFinder().run(tree: try s.scan().tree, options: o).groups.count == 1)
    }

    @Test func differencesOutsideTheSampledWindowsAreCaughtByTheFullHash() throws {
        let s = Sandbox()
        let a = s.file("x.bin", size: 3_000_000, seed: 7)
        let b = s.path("y.bin")
        try FileManager.default.copyItem(atPath: a, toPath: b)
        // Flip one byte far from the head, middle and tail windows. The copy is a clone, so write breaks sharing for one block.
        let fd = open(b, O_WRONLY); var byte: UInt8 = 0xFF
        pwrite(fd, &byte, 1, 700_001); close(fd)
        #expect(DuplicateFinder.sampleHash(a, 3_000_000) == DuplicateFinder.sampleHash(b, 3_000_000))
        #expect(DuplicateFinder().run(tree: try s.scan().tree).groups.isEmpty)
        #expect(!DuplicateFinder.identicalContents(a, b))
    }

    @Test func collisionsInThePreliminaryFilterDoNotCreateFalseGroups() throws {
        let s = Sandbox()
        for i in 0 ..< 6 { s.file("f\(i).bin", size: 100_000, seed: UInt8(i / 2)) }
        let colliding = DuplicateFinder(sampler: { _, _ in Data([1, 2, 3]) })
        let r = colliding.run(tree: try s.scan().tree)
        #expect(r.groups.count == 3)
        #expect(r.groups.allSatisfy { $0.files.count == 2 })
    }

    @Test func hardLinksAreOneFileNotDuplicates() throws {
        let s = Sandbox()
        let a = s.file("a.bin", size: 80_000, seed: 9)
        link(a, s.path("a-link.bin"))
        #expect(DuplicateFinder().run(tree: try s.scan().tree).groups.isEmpty)
        s.file("copy.bin", size: 80_000, seed: 9)
        let r = DuplicateFinder().run(tree: try s.scan().tree)
        #expect(r.groups.count == 1)
        #expect(r.groups[0].files.count == 2)
        let linked = r.groups[0].files.first { !$0.hardLinkPaths.isEmpty }!
        #expect(linked.hardLinkPaths.count == 1)
        // Removing one name of a hard-linked file frees nothing.
        #expect(r.groups[0].recoverable(removing: [linked.path]).maximum == 0)
    }

    @Test func clonesAreDuplicatesThatShareStorage() throws {
        let s = Sandbox()
        let a = s.file("orig.bin", size: 2_000_000, seed: 5)
        clonefile(a, s.path("clone.bin"), 0)
        let r = DuplicateFinder().run(tree: try s.scan().tree)
        #expect(r.groups.count == 1)
        #expect(r.groups[0].sharesStorage)
        let est = r.groups[0].recoverable(removing: [s.path("clone.bin")])
        #expect(est.minimum < 100_000)
        #expect(est.maximum >= 2_000_000)
        #expect(!est.isExact)
    }

    @Test func largeFilesAndUnreadableFiles() throws {
        let s = Sandbox()
        let big = s.file("big1.bin", size: 48_000_000, seed: 11)
        // A real copy (not a clone) so both are read in full.
        let data = try Data(contentsOf: URL(fileURLWithPath: big))
        FileManager.default.createFile(atPath: s.path("big2.bin"), contents: data)
        s.file("locked1.bin", size: 70_000, seed: 12)
        s.file("locked2.bin", size: 70_000, seed: 12)
        chmod(s.path("locked2.bin"), 0o000)
        let finder = DuplicateFinder()
        let r = finder.run(tree: try s.scan().tree)
        #expect(r.groups.count == 1)
        #expect(r.groups[0].logicalSize == 48_000_000)
        #expect(r.bytesHashed >= 96_000_000)
        #expect(r.unreadable == [s.path("locked2.bin")] || r.unreadable.isEmpty)
        #expect(finder.progress.stage == .done)
    }

    @Test func aFileThatChangedSinceTheScanIsDropped() throws {
        let s = Sandbox()
        s.file("a.bin", size: 50_000, seed: 1)
        s.file("b.bin", size: 50_000, seed: 1)
        let tree = try s.scan().tree
        let h = FileHandle(forWritingAtPath: s.path("b.bin"))!
        h.seekToEndOfFile(); h.write(Data([1, 2, 3])); try h.close()
        #expect(DuplicateFinder().run(tree: tree).groups.isEmpty)
        #expect(DuplicateFinder.fullHash(path: s.path("b.bin"), expectedSize: 50_000) == nil)
        #expect(DuplicateFinder.fullHash(path: s.path("b.bin")) != nil)
    }

    @Test func packageContentsAreSkippedUnlessAsked() throws {
        let s = Sandbox()
        s.file("One.app/Contents/Resources/asset.bin", size: 40_000, seed: 3)
        s.file("Two.app/Contents/Resources/asset.bin", size: 40_000, seed: 3)
        let tree = try s.scan().tree
        #expect(DuplicateFinder().run(tree: tree).groups.isEmpty)
        var o = DuplicateOptions(); o.includePackageContents = true
        #expect(DuplicateFinder().run(tree: tree, options: o).groups.count == 1)
    }

    @Test func cancellationReturnsNoGroups() throws {
        let s = Sandbox()
        for i in 0 ..< 20 { s.file("f\(i).bin", size: 300_000, seed: 1) }
        let f = DuplicateFinder()
        f.cancel()
        let r = f.run(tree: try s.scan().tree)
        #expect(r.cancelled && r.groups.isEmpty)
    }
}

@Suite struct SimilarImageTests {
    /// A deterministic picture: gradient background and a few shapes that depend on `seed`.
    static func picture(seed: Int, size: Int = 640) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        var x = UInt64(seed) &* 6364136223846793005 &+ 1442695040888963407
        func rnd() -> CGFloat { x = x &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((x >> 33) % 1000) / 1000 }
        let colors = [CGColor(red: rnd(), green: rnd(), blue: rnd(), alpha: 1), CGColor(red: rnd(), green: rnd(), blue: rnd(), alpha: 1)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: CGFloat(size) * rnd(), y: CGFloat(size)), options: [.drawsAfterEndLocation])
        for _ in 0 ..< 14 {
            ctx.setFillColor(CGColor(red: rnd(), green: rnd(), blue: rnd(), alpha: 1))
            let r = CGRect(x: rnd() * CGFloat(size), y: rnd() * CGFloat(size), width: rnd() * CGFloat(size) / 2.5 + 20, height: rnd() * CGFloat(size) / 2.5 + 20)
            if rnd() > 0.5 { ctx.fillEllipse(in: r) } else { ctx.fill(r) }
        }
        return ctx.makeImage()!
    }

    static func write(_ image: CGImage, to path: String, type: UTType = .jpeg, quality: Double = 0.9, scale: CGFloat = 1, crop: CGFloat = 0) {
        var img = image
        if crop > 0 {
            let inset = CGFloat(image.width) * crop
            img = image.cropping(to: CGRect(x: inset, y: inset, width: CGFloat(image.width) - 2 * inset, height: CGFloat(image.height) - 2 * inset))!
        }
        if scale != 1 {
            let w = Int(CGFloat(img.width) * scale), h = Int(CGFloat(img.height) * scale)
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            img = ctx.makeImage()!
        }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    @Test func resizedAndRecompressedCopiesAreGroupedAndUnrelatedImagesAreNot() throws {
        let s = Sandbox()
        let a = Self.picture(seed: 1), b = Self.picture(seed: 2)
        Self.write(a, to: s.path("p/a.jpg"))
        Self.write(a, to: s.path("p/a-small.jpg"), quality: 0.6, scale: 0.4)
        Self.write(a, to: s.path("p/a.png"), type: .png)
        Self.write(b, to: s.path("p/b.jpg"))
        for i in 3 ..< 9 { Self.write(Self.picture(seed: i), to: s.path("p/other\(i).jpg")) }
        var o = SimilarImageOptions(); o.minimumSize = 512
        let r = SimilarImageFinder().run(tree: try s.scan().tree, options: o)
        #expect(r.imagesExamined == 10)
        #expect(r.groups.count == 1)
        let names = Set(r.groups.first?.images.map { ($0.path as NSString).lastPathComponent } ?? [])
        #expect(names == ["a.jpg", "a-small.jpg", "a.png"])
        #expect(r.groups.first?.images.first?.pixelWidth == 640)
        #expect((r.groups.first?.confidence ?? 0) > 0.3)
    }

    @Test func thoroughModeFindsCrops() throws {
        let s = Sandbox()
        let a = Self.picture(seed: 21)
        Self.write(a, to: s.path("a.jpg"))
        Self.write(a, to: s.path("a-crop.jpg"), crop: 0.06)
        for i in 30 ..< 34 { Self.write(Self.picture(seed: i), to: s.path("o\(i).jpg")) }
        var o = SimilarImageOptions(); o.mode = .thorough
        let r = SimilarImageFinder().run(tree: try s.scan().tree, options: o)
        #expect(r.mode == .thorough)
        #expect(r.groups.count == 1)
        #expect(r.groups.first?.images.count == 2)
    }

    @Test func corruptImagesAreCountedNotCrashed() throws {
        let s = Sandbox()
        s.file("broken.jpg", size: 50_000, seed: 3)
        Self.write(Self.picture(seed: 5), to: s.path("ok.jpg"))
        let r = SimilarImageFinder().run(tree: try s.scan().tree)
        #expect(r.unreadable == 1)
        #expect(r.groups.isEmpty)
    }
}
