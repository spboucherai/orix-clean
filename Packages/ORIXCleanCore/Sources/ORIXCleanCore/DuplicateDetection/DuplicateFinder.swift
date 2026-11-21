// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/DuplicateDetection/DuplicateFinder.swift
// Description: Exact duplicate detection: size groups, sampled hash, full SHA-256, optional byte-for-byte verification.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import CryptoKit
import Darwin
import Foundation

public struct DuplicateOptions: Sendable {
    public var minimumSize: Int64 = 1
    /// Files inside packages (apps, photo libraries, bundles) are parts of a larger item and are skipped by default.
    public var includePackageContents = false
    public var under: Int32 = 0
    /// Hashing threads. 0 picks a value from the processor count.
    public var workers = 0
    public init() {}
}

public struct DuplicateFile: Sendable, Hashable, Identifiable, Codable {
    public var id: String { path }
    public var node: Int32
    public var path: String
    public var modified: Date
    public var allocatedSize: Int64
    /// -1 when unknown.
    public var privateSize: Int64
    public var fileID: UInt64
    /// APFS says this file may share blocks with another file.
    public var mayShareBlocks: Bool
    public var cloneID: UInt64
    /// Other names (hard links) of the same inode found in the scan. Removing one name frees nothing.
    public var hardLinkPaths: [String]
}

public struct DuplicateGroup: Sendable, Hashable, Identifiable, Codable {
    public var id: String { digest }
    /// SHA-256 of the content, hexadecimal.
    public var digest: String
    public var logicalSize: Int64
    public var files: [DuplicateFile]

    /// Logical bytes held by the copies beyond the first.
    public var redundantLogical: Int64 { logicalSize * Int64(max(0, files.count - 1)) }

    /// True when at least two members are APFS clones of each other: they share blocks, so removing one may free little.
    public var sharesStorage: Bool {
        let ids = files.filter { $0.cloneID != 0 }.map(\.cloneID)
        return Set(ids).count < ids.count || files.contains { $0.mayShareBlocks }
    }

    /// Space expected back if `removed` are removed and the rest are kept.
    public func recoverable(removing removed: Set<String>) -> RecoverableEstimate {
        var est = RecoverableEstimate.zero
        for f in files where removed.contains(f.path) {
            let maximum = f.allocatedSize
            var minimum = f.privateSize >= 0 ? f.privateSize : f.allocatedSize
            if !f.hardLinkPaths.isEmpty { minimum = 0 }
            est = est + RecoverableEstimate(minimum: minimum, maximum: f.hardLinkPaths.isEmpty ? maximum : 0)
        }
        return est
    }
}

public struct DuplicateProgress: Sendable {
    public enum Stage: String, Sendable { case grouping, sampling, hashing, done }
    public var stage: Stage = .grouping
    public var filesDone = 0
    public var filesTotal = 0
    public var bytesHashed: Int64 = 0
    public init() {}
}

public struct DuplicateResult: Sendable {
    public var groups: [DuplicateGroup]
    public var candidates: Int
    public var bytesHashed: Int64
    public var duration: TimeInterval
    public var unreadable: [String]
    public var cancelled: Bool
    public var redundantLogical: Int64 { groups.reduce(0) { $0 + $1.redundantLogical } }
}

public final class DuplicateFinder: @unchecked Sendable {
    public typealias SampleHasher = @Sendable (_ path: String, _ size: Int64) -> Data?

    private let lock = NSLock()
    private var state = DuplicateProgress()
    private var cancelledFlag = false
    private var unreadable: [String] = []
    private let sampler: SampleHasher

    /// `sampler` exists so tests can force collisions in the preliminary filter; the full hash still decides.
    public init(sampler: @escaping SampleHasher = DuplicateFinder.sampleHash) { self.sampler = sampler }

    public func cancel() { lock.lock(); cancelledFlag = true; lock.unlock() }
    public var progress: DuplicateProgress { lock.lock(); defer { lock.unlock() }; return state }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledFlag }
    private func update(_ body: (inout DuplicateProgress) -> Void) { lock.lock(); body(&state); lock.unlock() }

    /// Blocking. Run it off the main thread.
    public func run(tree: ScanTree, options: DuplicateOptions = DuplicateOptions()) -> DuplicateResult {
        let started = Date()
        let inside = options.includePackageContents ? [] : TreeQuery.packageMembership(tree)
        // 1. Candidates by size. Other names of an already-seen inode are attached to it, not compared.
        var bySize: [Int64: [Int32]] = [:]
        var linkNames: [UInt64: [Int32]] = [:]
        tree.forEachFile(under: options.under) { i, n in
            if n.logicalSize < max(1, options.minimumSize) || n.flags.contains(.dataless) { return }
            if !inside.isEmpty, inside[Int(i)] { return }
            if n.flags.contains(.hardLinkDuplicate) { linkNames[n.fileID, default: []].append(i); return }
            bySize[n.logicalSize, default: []].append(i)
        }
        var groups = bySize.filter { $0.value.count > 1 }.map { (size: $0.key, nodes: $0.value) }
        let candidates = groups.reduce(0) { $0 + $1.nodes.count }
        let workers = options.workers > 0 ? options.workers : max(2, min(6, ProcessInfo.processInfo.activeProcessorCount / 2))

        // 2. Sampled hash (head, middle, tail) to split size groups cheaply.
        update { $0.stage = .sampling; $0.filesTotal = candidates; $0.filesDone = 0 }
        var sampled: [(size: Int64, nodes: [Int32])] = []
        let flat = groups.flatMap { g in g.nodes.map { (g.size, $0) } }
        let sampleDigests = parallelMap(flat, workers: workers) { [sampler] item -> Data? in
            item.0 <= Int64(Self.sampleBytes * 3) ? Data() : sampler(tree.path(of: item.1), item.0)
        }
        var buckets: [SampleKey: [Int32]] = [:]
        for (k, item) in flat.enumerated() {
            guard let d = sampleDigests[k] else { continue }
            buckets[SampleKey(size: item.0, digest: d), default: []].append(item.1)
        }
        for (k, v) in buckets where v.count > 1 { sampled.append((k.size, v)) }
        groups = sampled

        // 3. Full SHA-256.
        let toHash = groups.flatMap { g in g.nodes.map { (g.size, $0) } }
        update { $0.stage = .hashing; $0.filesTotal = toHash.count; $0.filesDone = 0 }
        let digests = parallelMap(toHash, workers: workers) { [self] item -> Data? in
            let path = tree.path(of: item.1)
            let d = Self.fullHash(path: path, expectedSize: item.0, isCancelled: { self.isCancelled }) { n in
                self.update { $0.bytesHashed += Int64(n) }
            }
            if d == nil, !self.isCancelled { self.lock.lock(); self.unreadable.append(path); self.lock.unlock() }
            return d
        }
        var final: [SampleKey: [Int32]] = [:]
        for (k, item) in toHash.enumerated() {
            guard let d = digests[k] else { continue }
            final[SampleKey(size: item.0, digest: d), default: []].append(item.1)
        }
        var result: [DuplicateGroup] = []
        for (k, nodes) in final where nodes.count > 1 {
            let files = nodes.map { i -> DuplicateFile in
                let n = tree[i]
                return DuplicateFile(node: i, path: tree.path(of: i), modified: Date(timeIntervalSince1970: TimeInterval(n.modified)),
                                     allocatedSize: n.allocatedSize, privateSize: n.privateSize, fileID: n.fileID,
                                     mayShareBlocks: n.flags.contains(.mayShareBlocks), cloneID: tree.cloneIDs[i] ?? 0,
                                     hardLinkPaths: n.flags.contains(.hardLinked) ? (linkNames[n.fileID] ?? []).map { tree.path(of: $0) } : [])
            }.sorted { $0.path < $1.path }
            result.append(DuplicateGroup(digest: k.digest.map { String(format: "%02x", $0) }.joined(), logicalSize: k.size, files: files))
        }
        result.sort { $0.redundantLogical > $1.redundantLogical || ($0.redundantLogical == $1.redundantLogical && $0.digest < $1.digest) }
        update { $0.stage = .done }
        lock.lock(); let bad = unreadable; let hashed = state.bytesHashed; let cancelled = cancelledFlag; lock.unlock()
        return DuplicateResult(groups: cancelled ? [] : result, candidates: candidates, bytesHashed: hashed,
                               duration: Date().timeIntervalSince(started), unreadable: bad, cancelled: cancelled)
    }

    private struct SampleKey: Hashable { var size: Int64; var digest: Data }

    private func parallelMap<T: Sendable>(_ items: [T], workers: Int, _ body: @escaping @Sendable (T) -> Data?) -> [Data?] {
        guard !items.isEmpty else { return [] }
        let out = UnsafeMutablePointer<Data?>.allocate(capacity: items.count)
        out.initialize(repeating: nil, count: items.count)
        defer { out.deinitialize(count: items.count); out.deallocate() }
        nonisolated(unsafe) let slots = out
        let next = NSLock()
        nonisolated(unsafe) var cursor = 0
        let group = DispatchGroup()
        for _ in 0 ..< min(workers, items.count) {
            group.enter()
            let t = Thread { [self] in
                defer { group.leave() }
                while true {
                    next.lock(); let i = cursor; cursor += 1; next.unlock()
                    if i >= items.count || isCancelled { return }
                    let d = body(items[i])
                    slots[i] = d
                    lock.lock()
                    state.filesDone += 1
                    lock.unlock()
                }
            }
            t.qualityOfService = .utility
            t.start()
        }
        group.wait()
        return (0 ..< items.count).map { out[$0] }
    }

    static let sampleBytes = 16 * 1024

    /// SHA-256 over three 16 KiB windows: head, middle and tail. Does not populate the unified buffer cache.
    public static let sampleHash: SampleHasher = { path, size in
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: sampleBytes)
        for offset in [0, max(0, size / 2 - Int64(sampleBytes / 2)), max(0, size - Int64(sampleBytes))] {
            let n = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, sampleBytes, off_t(offset)) }
            guard n >= 0 else { return nil }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[0 ..< n])) }
        }
        return Data(hasher.finalize())
    }

    /// Streaming SHA-256. Returns nil when the file cannot be read or its size is not the scanned size (it changed).
    public static func fullHash(path: String, expectedSize: Int64? = nil, isCancelled: () -> Bool = { false },
                                onBytes: (Int) -> Void = { _ in }) -> Data? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        if let expectedSize, Int64(st.st_size) != expectedSize { return nil }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = SHA256()
        let chunk = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16384)
        defer { buffer.deallocate() }
        var total: Int64 = 0
        while true {
            if isCancelled() { return nil }
            let n = read(fd, buffer, chunk)
            if n < 0 { if errno == EINTR { continue }; return nil }
            if n == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: n))
            total += Int64(n)
            onBytes(n)
        }
        if let expectedSize, total != expectedSize { return nil }
        return Data(hasher.finalize())
    }

    /// Byte-for-byte comparison. Used right before a duplicate is removed.
    public static func identicalContents(_ a: String, _ b: String) -> Bool {
        let fa = open(a, O_RDONLY | O_NOFOLLOW | O_CLOEXEC), fb = open(b, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        defer { if fa >= 0 { close(fa) }; if fb >= 0 { close(fb) } }
        guard fa >= 0, fb >= 0 else { return false }
        var sa = stat(), sb = stat()
        guard fstat(fa, &sa) == 0, fstat(fb, &sb) == 0, sa.st_size == sb.st_size else { return false }
        guard (sa.st_mode & S_IFMT) == S_IFREG, (sb.st_mode & S_IFMT) == S_IFREG else { return false }
        if sa.st_dev == sb.st_dev, sa.st_ino == sb.st_ino { return true }
        let chunk = 1 << 20
        let ba = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16384)
        let bb = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16384)
        defer { ba.deallocate(); bb.deallocate() }
        var offset: off_t = 0
        while true {
            let na = pread(fa, ba, chunk, offset), nb = pread(fb, bb, chunk, offset)
            if na < 0 || nb < 0 || na != nb { return false }
            if na == 0 { return true }
            if memcmp(ba, bb, na) != 0 { return false }
            offset += off_t(na)
        }
    }
}
