// ORIX Clean — Packages/ORIXCleanCore/Sources/orix-bench/Fixture.swift
// Description: Builds a disposable sample home folder with real files (real sizes) for UI tests, screenshots and benchmarks.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Fixture {
    nonisolated(unsafe) static var rng: UInt64 = 0x9E3779B97F4A7C15
    static func next() -> UInt64 { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng }

    static func write(_ path: String, bytes: Int, seed: UInt64? = nil, ageDays: Int = 0) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        var state = seed ?? next()
        var block = [UInt64](repeating: 0, count: 8192)
        var left = bytes
        while left > 0 {
            for i in block.indices { state ^= state << 13; state ^= state >> 7; state ^= state << 17; block[i] = state }
            let n = min(left, block.count * 8)
            _ = block.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, n) }
            left -= n
        }
        close(fd)
        age(path, ageDays)
    }

    static func age(_ path: String, _ days: Int) {
        guard days > 0 else { return }
        let t = time(nil) - days * 86400
        var times = [timeval(tv_sec: t, tv_usec: 0), timeval(tv_sec: t, tv_usec: 0)]
        utimes(path, &times)
    }

    static func picture(seed: Int, size: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size * 3 / 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        var x = UInt64(seed) &* 6364136223846793005 &+ 1442695040888963407
        func rnd() -> CGFloat { x = x &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((x >> 33) % 1000) / 1000 }
        let w = CGFloat(size), h = CGFloat(size * 3 / 4)
        let sky = [CGColor(red: 0.1 + rnd() * 0.5, green: 0.3 + rnd() * 0.5, blue: 0.6 + rnd() * 0.4, alpha: 1),
                   CGColor(red: 0.9, green: 0.5 + rnd() * 0.4, blue: 0.3 + rnd() * 0.4, alpha: 1)] as CFArray
        ctx.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1])!, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: rnd() * w * 0.8, y: h * (0.5 + rnd() * 0.3), width: w * 0.12, height: w * 0.12))
        for layer in 0 ..< 4 {
            let shade = 0.15 + CGFloat(layer) * 0.12
            ctx.setFillColor(CGColor(red: shade * rnd(), green: shade + rnd() * 0.2, blue: shade + rnd() * 0.15, alpha: 1))
            ctx.move(to: CGPoint(x: 0, y: 0))
            var px: CGFloat = 0
            while px <= w { ctx.addLine(to: CGPoint(x: px, y: h * (0.45 - CGFloat(layer) * 0.1) * (0.5 + rnd() * 0.7))); px += w / CGFloat(6 + layer * 3) }
            ctx.addLine(to: CGPoint(x: w, y: 0))
            ctx.closePath(); ctx.fillPath()
        }
        return ctx.makeImage()!
    }

    static func save(_ image: CGImage, _ path: String, type: UTType = .jpeg, quality: Double = 0.92, scale: CGFloat = 1, ageDays: Int = 0) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        var img = image
        if scale != 1 {
            let w = Int(CGFloat(img.width) * scale), h = Int(CGFloat(img.height) * scale)
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            img = ctx.makeImage()!
        }
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, type.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        age(path, ageDays)
    }

    static func app(_ home: String, _ name: String, id: String, version: String, mb: Double) {
        let base = "\(home)/Applications/\(name).app/Contents"
        try? FileManager.default.createDirectory(atPath: base + "/MacOS", withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": version, "CFBundleVersion": "1",
                                    "CFBundleExecutable": name, "CFBundlePackageType": "APPL"]
        try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: URL(fileURLWithPath: base + "/Info.plist"))
        write(base + "/MacOS/\(name)", bytes: Int(mb * 0.3 * 1e6))
        write(base + "/Resources/Assets.car", bytes: Int(mb * 0.5 * 1e6))
        write(base + "/Frameworks/Engine.framework/Engine", bytes: Int(mb * 0.2 * 1e6))
    }

    /// `scale` multiplies every size (1 ≈ 0.9 GB on disk).
    static func build(home: String, scale: Double = 1) {
        func mb(_ v: Double) -> Int { Int(v * scale * 1e6) }
        let fm = FileManager.default
        try? fm.removeItem(atPath: home)
        // Documents and media
        write(home + "/Movies/Lisbon trip 4K.mov", bytes: mb(180), ageDays: 420)
        write(home + "/Movies/Conference talk.mp4", bytes: mb(95), ageDays: 60)
        write(home + "/Movies/Screen Recording 2026-03-02.mov", bytes: mb(48), ageDays: 260)
        write(home + "/Music/Mixes/Summer set.flac", bytes: mb(38), ageDays: 500)
        write(home + "/Music/Mixes/Podcast episode 12.mp3", bytes: mb(21), ageDays: 90)
        for i in 1 ... 14 { write(home + "/Documents/Projects/Atlas/report-v\(i).pdf", bytes: mb(Double(1 + i % 5)), ageDays: 20 * i) }
        for i in 1 ... 30 { write(home + "/Documents/Notes/note-\(i).md", bytes: 2000 + i * 300, ageDays: i * 9) }
        write(home + "/Documents/Projects/Atlas/dataset.csv", bytes: mb(42), ageDays: 130)
        write(home + "/Documents/Archive/2024 taxes.zip", bytes: mb(26), ageDays: 600)
        write(home + "/Documents/Archive/Old laptop backup.dmg", bytes: mb(120), ageDays: 800)
        // Exact duplicates (real copies, not clones) and one APFS clone
        let dupSeed: UInt64 = 777
        write(home + "/Documents/Projects/Atlas/dataset copy.csv", bytes: mb(42), seed: 4242, ageDays: 30)
        write(home + "/Documents/Projects/Atlas/dataset.csv", bytes: mb(42), seed: 4242, ageDays: 130)
        write(home + "/Movies/Conference talk.mp4", bytes: mb(95), seed: dupSeed, ageDays: 60)
        write(home + "/Downloads/Conference talk (1).mp4", bytes: mb(95), seed: dupSeed, ageDays: 58)
        write(home + "/Desktop/Conference talk.mp4", bytes: mb(95), seed: dupSeed, ageDays: 12)
        write(home + "/Music/Mixes/Summer set (copy).flac", bytes: mb(38), seed: 991, ageDays: 3)
        write(home + "/Music/Mixes/Summer set.flac", bytes: mb(38), seed: 991, ageDays: 500)
        clonefile(home + "/Documents/Archive/Old laptop backup.dmg", home + "/Documents/Archive/Old laptop backup (clone).dmg", 0)
        // Pictures: originals, resized/recompressed versions, unrelated pictures
        for i in 1 ... 18 {
            let img = picture(seed: i * 31, size: 1600)
            save(img, home + "/Pictures/2026 Hike/IMG_\(4100 + i).jpg", ageDays: 40)
            if i % 3 == 0 { save(img, home + "/Pictures/2026 Hike/IMG_\(4100 + i) small.jpg", quality: 0.6, scale: 0.4, ageDays: 39) }
            if i % 6 == 0 { save(img, home + "/Pictures/Exports/IMG_\(4100 + i).png", type: .png, ageDays: 10) }
            if i % 9 == 0 { save(img, home + "/Desktop/IMG_\(4100 + i) edit.jpg", quality: 0.8, scale: 0.75, ageDays: 5) }
        }
        // Downloads
        write(home + "/Downloads/Sketcher-4.2.dmg", bytes: mb(64), ageDays: 200)
        write(home + "/Downloads/Renderly Installer.pkg", bytes: mb(31), ageDays: 150)
        write(home + "/Downloads/Xcode_27_beta.xip", bytes: mb(88), ageDays: 110)
        write(home + "/Downloads/fonts-pack.zip", bytes: mb(12), ageDays: 45)
        write(home + "/Downloads/fonts-pack/Inter.ttf", bytes: mb(3), ageDays: 45)
        write(home + "/Downloads/fonts-pack/Fraunces.ttf", bytes: mb(4), ageDays: 45)
        write(home + "/Downloads/dataset-raw.tar.gz", bytes: mb(27), ageDays: 14)
        write(home + "/Downloads/linux-image.iso.crdownload", bytes: mb(19), ageDays: 70)
        write(home + "/Downloads/invoice-2026-10.pdf", bytes: 180_000, ageDays: 20)
        // Applications and their Library files
        app(home, "Sketcher", id: "com.vectorworks.sketcher", version: "4.2", mb: 46 * scale)
        app(home, "Renderly", id: "io.renderly.app", version: "2.0.1", mb: 28 * scale)
        app(home, "Notably", id: "app.notably.mac", version: "1.9", mb: 12 * scale)
        write(home + "/Library/Application Support/com.vectorworks.sketcher/library.db", bytes: mb(14))
        write(home + "/Library/Application Support/Sketcher/Brushes.bundle/brushes.dat", bytes: mb(6))
        write(home + "/Library/Caches/com.vectorworks.sketcher/thumbnails.cache", bytes: mb(22))
        write(home + "/Library/Preferences/com.vectorworks.sketcher.plist", bytes: 4000)
        write(home + "/Library/Saved Application State/com.vectorworks.sketcher.savedState/windows.plist", bytes: 9000)
        write(home + "/Library/Caches/io.renderly.app/frames.cache", bytes: mb(34))
        write(home + "/Library/Caches/app.notably.mac/sync.cache", bytes: mb(5))
        write(home + "/Library/Caches/Google/Chrome/Default/Cache/Cache_Data/data_1", bytes: mb(41))
        write(home + "/Library/Caches/Firefox/Profiles/a1b2c3.default/cache2/entries/blob", bytes: mb(17))
        write(home + "/Library/Logs/Renderly/render.log", bytes: mb(8), ageDays: 3)
        write(home + "/Library/Logs/DiagnosticReports/Sketcher-2026-09-01.ips", bytes: 600_000, ageDays: 80)
        // Leftovers of applications that are not installed
        write(home + "/Library/Application Support/com.oldstudio.pixelforge/projects.db", bytes: mb(11), ageDays: 400)
        write(home + "/Library/Caches/com.oldstudio.pixelforge/render.cache", bytes: mb(7), ageDays: 400)
        write(home + "/Library/Preferences/com.oldstudio.pixelforge.plist", bytes: 20_000, ageDays: 400)
        write(home + "/Library/Containers/net.tinytools.clipkeeper/Data/Library/store.sqlite", bytes: mb(3), ageDays: 300)
        // Developer data
        for (name, size, days) in [("Atlas-bqxmfldzjgheuz", 58.0, 2), ("Renderly-ckwppqnvtryhga", 44.0, 35), ("Playground-akdlsiejfhgqwe", 16.0, 220)] {
            write(home + "/Library/Developer/Xcode/DerivedData/\(name)/Build/Products/Debug/app.o", bytes: mb(size * 0.6), ageDays: days)
            write(home + "/Library/Developer/Xcode/DerivedData/\(name)/Index.noindex/DataStore/index.db", bytes: mb(size * 0.4), ageDays: days)
        }
        write(home + "/Library/Developer/Xcode/Archives/2025-11-02/Atlas 2025-11-02.xcarchive/dSYMs/Atlas.dSYM", bytes: mb(24), ageDays: 380)
        write(home + "/Library/Developer/Xcode/iOS DeviceSupport/iPhone18,2 26.1 (23B82)/Symbols/dyld_shared_cache", bytes: mb(52), ageDays: 150)
        write(home + "/Library/Developer/CoreSimulator/Caches/dyld/dyld_sim_shared_cache", bytes: mb(30), ageDays: 20)
        write(home + "/Library/Caches/Homebrew/downloads/node--22.tar.gz", bytes: mb(18), ageDays: 60)
        write(home + "/Library/Caches/org.swift.swiftpm/repositories/swift-collections/pack", bytes: mb(9), ageDays: 60)
        write(home + "/.npm/_cacache/content-v2/sha512/aa/blob", bytes: mb(26), ageDays: 30)
        write(home + "/Library/Caches/pip/wheels/numpy.whl", bytes: mb(15), ageDays: 90)
        write(home + "/Developer/webshop/package.json", bytes: 900)
        write(home + "/Developer/webshop/src/index.ts", bytes: 4000)
        for i in 0 ..< 40 { write(home + "/Developer/webshop/node_modules/pkg-\(i)/index.js", bytes: mb(0.6)) }
        write(home + "/Developer/atlas-cli/Package.swift", bytes: 700)
        write(home + "/Developer/atlas-cli/.build/debug/atlas", bytes: mb(21))
        // Trash
        write(home + "/.Trash/Old presentation.key", bytes: mb(33), ageDays: 9)
        write(home + "/.Trash/screenshots/shot-1.png", bytes: mb(4), ageDays: 9)
        write(home + "/.Trash/screenshots/shot-2.png", bytes: mb(4), ageDays: 9)
        for d in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Library", "Public"] {
            try? fm.createDirectory(atPath: home + "/" + d, withIntermediateDirectories: true)
        }
    }
}
