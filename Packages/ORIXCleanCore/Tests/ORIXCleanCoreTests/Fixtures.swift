// ORIX Clean — Packages/ORIXCleanCore/Tests/ORIXCleanCoreTests/Fixtures.swift
// Description: Disposable directories and disk images for tests. Nothing here touches real user data.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation
@testable import ORIXCleanCore

final class Sandbox: @unchecked Sendable {
    let root: String
    init(_ label: String = "t") {
        let base = (NSTemporaryDirectory() as NSString).appendingPathComponent("orixclean-tests-\(label)-\(UUID().uuidString.prefix(8))")
        try! FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        root = (base as NSString).resolvingSymlinksInPath
    }

    deinit {
        _ = try? FileManager.default.subpathsOfDirectory(atPath: root).forEach { chmod(root + "/" + $0, 0o700) }
        try? FileManager.default.removeItem(atPath: root)
    }

    func path(_ rel: String) -> String { root + "/" + rel }

    @discardableResult
    func dir(_ rel: String) -> String {
        try! FileManager.default.createDirectory(atPath: path(rel), withIntermediateDirectories: true)
        return path(rel)
    }

    @discardableResult
    func file(_ rel: String, size: Int, seed: UInt8 = 1) -> String {
        dir((rel as NSString).deletingLastPathComponent)
        var bytes = [UInt8](repeating: 0, count: size)
        var x = UInt32(seed) &* 2654435761 &+ 12345
        for i in 0 ..< size { x = x &* 1664525 &+ 1013904223; bytes[i] = UInt8(truncatingIfNeeded: x >> 24) }
        FileManager.default.createFile(atPath: path(rel), contents: Data(bytes))
        return path(rel)
    }

    @discardableResult
    func text(_ rel: String, _ s: String) -> String {
        dir((rel as NSString).deletingLastPathComponent)
        FileManager.default.createFile(atPath: path(rel), contents: Data(s.utf8))
        return path(rel)
    }

    func scan(_ rel: String = "", options: ScanOptions = ScanOptions()) throws -> ScanResult {
        try FileScanner(root: rel.isEmpty ? root : path(rel), options: options).run()
    }
}

func allocated(_ path: String) -> Int64 {
    var st = stat()
    lstat(path, &st)
    return Int64(st.st_blocks) * 512
}

@discardableResult
func shell(_ launch: String, _ args: [String]) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launch)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// A small APFS disk image mounted at a private mount point.
final class TestVolume: @unchecked Sendable {
    let image: String
    let mountPoint: String
    private(set) var mounted = false

    init?(sizeMB: Int = 24, readOnlyAfter populate: ((String) -> Void)? = nil, mountAt: String? = nil) {
        let base = (NSTemporaryDirectory() as NSString).appendingPathComponent("orixclean-vol-\(UUID().uuidString.prefix(8))")
        image = base + ".dmg"
        mountPoint = mountAt ?? ((base + "-mnt") as NSString).resolvingSymlinksInPath
        try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        guard shell("/usr/bin/hdiutil", ["create", "-size", "\(sizeMB)m", "-fs", "APFS", "-volname", "ORIXTest", "-quiet", image]).status == 0 else { return nil }
        guard attach(readOnly: false) else { return nil }
        if let populate {
            populate(mountPoint)
            detach()
            guard attach(readOnly: true) else { return nil }
        }
    }

    func attach(readOnly: Bool) -> Bool {
        var args = ["attach", image, "-nobrowse", "-mountpoint", mountPoint, "-quiet", "-owners", "on"]
        if readOnly { args.append("-readonly") }
        mounted = shell("/usr/bin/hdiutil", args).status == 0
        return mounted
    }

    func detach() {
        if mounted { shell("/usr/bin/hdiutil", ["detach", mountPoint, "-force", "-quiet"]); mounted = false }
    }

    deinit {
        detach()
        try? FileManager.default.removeItem(atPath: image)
        try? FileManager.default.removeItem(atPath: mountPoint)
    }
}

struct FakeTrasher: Trasher {
    var failing: Set<String> = []
    var error: NSError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    let bin: String
    func trash(_ url: URL) throws -> URL? {
        if failing.contains(url.path) { throw error }
        let dest = URL(fileURLWithPath: bin + "/" + UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    func remove(_ url: URL) throws {
        if failing.contains(url.path) { throw error }
        try FileManager.default.removeItem(at: url)
    }
}

func item(_ path: String, category: CleanupCategory = .other, risk: Risk = .low, verify: String? = nil, close: [String] = []) -> CleanupItem {
    CleanupItem(path: path, category: category, risk: risk, reason: "test", consequence: "test", measurement: Measure.item(path) ?? Measurement(),
                closeFirst: close, verifyAgainst: verify)
}
