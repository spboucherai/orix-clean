// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/FileScanner/FileScanner.swift
// Description: Parallel, cancellable, pausable directory traversal that builds a ScanTree. Never follows symlinks.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation

public struct ScanOptions: Sendable {
    /// Stay on the device of the root. Mount points and other devices become `.boundary` nodes.
    public var stayOnDevice = true
    /// Additional devices the scan may enter (the Data volume when scanning the startup volume from "/").
    public var allowedDevices: Set<Int32> = []
    /// Absolute paths that are not traversed.
    public var excludedPaths: Set<String> = []
    /// Ask APFS for private size / clone id / sharing flags.
    public var measureSharing = true
    /// Number of traversal threads. 0 picks a value from the processor count and thermal state.
    public var workers = 0
    public init() {}

    /// Options for scanning the startup volume from "/": enters the firmlinked Data volume, skips /System/Volumes
    /// (the same data seen a second time), /Volumes (other volumes) and /dev.
    public static func startupVolume() -> ScanOptions {
        var o = ScanOptions()
        var st = stat()
        if stat("/System/Volumes/Data", &st) == 0 { o.allowedDevices.insert(st.st_dev) }
        o.excludedPaths = ["/System/Volumes", "/Volumes", "/dev", "/.vol"]
        return o
    }
}

public struct ScanIssue: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable {
        case permissionDenied, vanished, ioError, pathTooLong
    }
    public var path: String
    public var kind: Kind
    public var code: Int32
    public var message: String { String(cString: strerror(code)) }
}

public struct ScanProgress: Sendable {
    public var files: Int = 0
    public var directories: Int = 0
    public var allocatedBytes: Int64 = 0
    public var issues: Int = 0
    public var currentPath: String = ""
    public var elapsed: TimeInterval = 0
    public init() {}
    init(files: Int, directories: Int, allocatedBytes: Int64, issues: Int, currentPath: String, elapsed: TimeInterval) {
        self.files = files; self.directories = directories; self.allocatedBytes = allocatedBytes; self.issues = issues
        self.currentPath = currentPath; self.elapsed = elapsed
    }
}

public struct ScanResult: Sendable {
    public let tree: ScanTree
    public let issues: [ScanIssue]
    public let started: Date
    public let duration: TimeInterval
    public let files: Int
    public let directories: Int
    public let cancelled: Bool
    /// True when the filesystem reported APFS private sizes for regular files.
    public let sharingMeasured: Bool
    public var filesPerSecond: Double { duration > 0 ? Double(files + directories) / duration : 0 }
}

public enum ScanError: Error, Sendable, Equatable {
    case rootNotFound(String)
    case rootNotDirectory(String)
    case rootUnreadable(String, Int32)
}

/// Directory names that Finder shows as one item.
public enum PackageTypes {
    public static let extensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "appex", "xpc", "photoslibrary", "musiclibrary", "tvlibrary",
        "aplibrary", "imovielibrary", "fcpbundle", "logicx", "band", "xcodeproj", "xcworkspace", "playground", "rtfd",
        "pages", "numbers", "key", "sparsebundle", "pkg", "mpkg", "prefpane", "qlgenerator", "saver", "component",
        "vst", "vst3", "lproj", "xcarchive", "dsym", "docset", "scptd", "wdgt", "download", "photolibrary", "pvm", "vmwarevm", "utm",
    ]
}

/// One scan. Create, call `run()` from a background context, observe `progress`, and call `cancel()` / `pause()` at will.
public final class FileScanner: @unchecked Sendable {
    private let rootPath: String
    private let options: ScanOptions

    private let lock = NSCondition()
    private var queue: [(node: Int32, path: String)] = []
    private var active = 0
    private var cancelledFlag = false
    private var pausedFlag = false
    private var tree: ScanTree!
    private var issues: [ScanIssue] = []
    private var seenDirectories = Set<UInt64>()
    private var seenHardLinks = Set<[UInt64]>()
    private var fileCount = 0
    private var dirCount = 0
    private var bytes: Int64 = 0
    private var current = ""
    private var sawPrivate = false
    private var startTime = Date()
    private var rootDevice: Int32 = 0

    public init(root: String, options: ScanOptions = ScanOptions()) {
        var path = (root as NSString).standardizingPath
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        self.rootPath = path
        self.options = options
    }

    public func cancel() {
        lock.lock(); cancelledFlag = true; pausedFlag = false; lock.broadcast(); lock.unlock()
    }

    public func pause() { lock.lock(); pausedFlag = true; lock.unlock() }
    public func resume() { lock.lock(); pausedFlag = false; lock.broadcast(); lock.unlock() }
    public var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return pausedFlag }

    public var progress: ScanProgress {
        lock.lock(); defer { lock.unlock() }
        return ScanProgress(files: fileCount, directories: dirCount, allocatedBytes: bytes, issues: issues.count,
                            currentPath: current, elapsed: Date().timeIntervalSince(startTime))
    }

    /// Blocking. Run it off the main thread.
    public func run() throws -> ScanResult {
        var st = stat()
        guard lstat(rootPath, &st) == 0 else { throw ScanError.rootNotFound(rootPath) }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { throw ScanError.rootNotDirectory(rootPath) }
        let probe = DirectoryReader.open(rootPath)
        guard probe >= 0 else { throw ScanError.rootUnreadable(rootPath, errno) }
        close(probe)

        startTime = Date()
        rootDevice = st.st_dev
        tree = ScanTree(rootPath: rootPath, rootDevice: st.st_dev)
        tree.nodes.reserveCapacity(1 << 16)
        tree.nodes.append(ScanNode(nameOffset: 0, nameLength: 0, flags: [.directory], parent: -1, childStart: 0, childCount: 0,
                                   fileCount: 0, logicalSize: 0, allocatedSize: 0, privateSize: 0,
                                   modified: Int64(st.st_mtimespec.tv_sec), fileID: UInt64(st.st_ino)))
        seenDirectories.insert(Self.key(st.st_dev, UInt64(st.st_ino)))
        queue = [(0, rootPath)]
        dirCount = 1

        var workerCount = options.workers
        if workerCount <= 0 {
            // Measured (docs/development/performance.md): directory enumeration is bound by the filesystem, not by cores.
            // Three threads give ~95 % of the best throughput for a third of the CPU time of eight.
            workerCount = min(3, max(1, ProcessInfo.processInfo.activeProcessorCount))
            switch ProcessInfo.processInfo.thermalState {
            case .serious, .critical: workerCount = 1
            default: break
            }
            if ProcessInfo.processInfo.isLowPowerModeEnabled { workerCount = 1 }
        }
        let group = DispatchGroup()
        for _ in 0 ..< workerCount {
            group.enter()
            let t = Thread { [self] in
                worker()
                group.leave()
            }
            t.qualityOfService = .userInitiated
            t.stackSize = 1 << 20
            t.start()
        }
        group.wait()
        aggregate()
        let result = ScanResult(tree: tree, issues: issues, started: startTime, duration: Date().timeIntervalSince(startTime),
                                files: fileCount, directories: dirCount, cancelled: cancelledFlag, sharingMeasured: sawPrivate)
        return result
    }

    private static func key(_ dev: Int32, _ id: UInt64) -> UInt64 { (UInt64(UInt32(bitPattern: dev)) << 40) ^ id }

    private func worker() {
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        var batch = DirectoryBatch()
        while true {
            lock.lock()
            while (queue.isEmpty && active > 0 || pausedFlag) && !cancelledFlag { lock.wait() }
            if cancelledFlag || queue.isEmpty {
                lock.unlock()
                lock.lock(); lock.broadcast(); lock.unlock()
                return
            }
            let item = queue.removeLast()
            active += 1
            current = item.path
            lock.unlock()

            batch.entries.removeAll(keepingCapacity: true)
            batch.names.removeAll(keepingCapacity: true)
            var failure: Int32 = 0
            let fd = DirectoryReader.open(item.path)
            var opened = stat()
            if fd < 0 {
                failure = errno
            } else if options.stayOnDevice, item.node != 0, fstat(fd, &opened) == 0, opened.st_dev != rootDevice,
                      !options.allowedDevices.contains(opened.st_dev) {
                // A volume is mounted here: the directory entry reports the covered folder, the open descriptor the mounted one.
                close(fd)
                lock.lock()
                tree.nodes[Int(item.node)].flags.insert(.boundary)
                active -= 1
                lock.broadcast()
                lock.unlock()
                continue
            } else {
                failure = DirectoryReader.read(fd: fd, extended: options.measureSharing, buffer: buffer, bufferSize: bufferSize, into: &batch)
                close(fd)
            }
            commit(item: item, batch: batch, failure: failure)
        }
    }

    private func issueKind(_ code: Int32) -> ScanIssue.Kind {
        switch code {
        case EACCES, EPERM: return .permissionDenied
        case ENOENT, ENOTDIR: return .vanished
        case ENAMETOOLONG: return .pathTooLong
        default: return .ioError
        }
    }

    private func commit(item: (node: Int32, path: String), batch: DirectoryBatch, failure: Int32) {
        lock.lock()
        defer {
            active -= 1
            lock.broadcast()
            lock.unlock()
        }
        if failure != 0 {
            issues.append(ScanIssue(path: item.path, kind: issueKind(failure), code: failure))
            if failure == EACCES || failure == EPERM { tree.nodes[Int(item.node)].flags.insert(.unreadable) }
            if batch.entries.isEmpty { return }
        }
        let start = Int32(tree.nodes.count)
        let nameBase = tree.names.count
        guard nameBase + batch.names.count < Int(UInt32.max), tree.nodes.count + batch.entries.count < Int(Int32.max) else {
            issues.append(ScanIssue(path: item.path, kind: .ioError, code: EOVERFLOW))
            return
        }
        tree.names.append(contentsOf: batch.names)
        tree.nodes[Int(item.node)].childStart = start
        tree.nodes[Int(item.node)].childCount = Int32(batch.entries.count)
        var index = start
        for e in batch.entries {
            var flags: NodeFlags = []
            var node = ScanNode(nameOffset: UInt32(nameBase + e.nameOffset), nameLength: UInt16(min(e.nameLength, Int(UInt16.max))), flags: [],
                                parent: item.node, childStart: 0, childCount: 0, fileCount: 0, logicalSize: 0, allocatedSize: 0,
                                privateSize: 0, modified: e.modified, fileID: e.fileID)
            if e.error != 0 {
                issues.append(ScanIssue(path: item.path + "/" + entryName(batch, e), kind: issueKind(e.error), code: e.error))
            }
            switch e.objType {
            case DirectoryReader.vdir:
                flags.insert(.directory)
                dirCount += 1
                let name = entryName(batch, e)
                let childPath = item.path == "/" ? "/" + name : item.path + "/" + name
                if let dot = name.lastIndex(of: "."), PackageTypes.extensions.contains(name[name.index(after: dot)...].lowercased()) {
                    flags.insert(.package)
                }
                let foreign = e.device != tree.rootDevice && !options.allowedDevices.contains(e.device)
                if e.bsdFlags & UInt32(SF_DATALESS) != 0 {
                    flags.insert(.dataless)
                } else if options.excludedPaths.contains(childPath) {
                    flags.insert(.skipped)
                } else if options.stayOnDevice, foreign || (e.mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0 && foreign) {
                    flags.insert(.boundary)
                } else if e.error == 0, seenDirectories.insert(Self.key(e.device, e.fileID)).inserted {
                    queue.append((index, childPath))
                }
            case DirectoryReader.vreg:
                fileCount += 1
                node.fileCount = 1
                node.logicalSize = e.logicalSize
                node.allocatedSize = e.allocatedSize
                node.privateSize = e.privateSize
                if e.privateSize >= 0 { sawPrivate = true }
                if e.bsdFlags & UInt32(SF_DATALESS) != 0 { flags.insert(.dataless) }
                if e.bsdFlags & UInt32(UF_COMPRESSED) != 0 { flags.insert(.compressed) }
                if e.extFlags & UInt64(EF_MAY_SHARE_BLOCKS) != 0 { flags.insert(.mayShareBlocks) }
                if e.extFlags & UInt64(EF_IS_SPARSE) != 0 { flags.insert(.sparse) }
                if e.cloneID != 0, flags.contains(.mayShareBlocks) { tree.cloneIDs[index] = e.cloneID }
                if e.linkCount > 1 {
                    flags.insert(.hardLinked)
                    if !seenHardLinks.insert([UInt64(UInt32(bitPattern: e.device)), e.fileID]).inserted { flags.insert(.hardLinkDuplicate) }
                }
                if !flags.contains(.hardLinkDuplicate) { bytes += e.allocatedSize }
            case DirectoryReader.vlnk:
                flags.insert(.symlink)
                node.logicalSize = e.logicalSize
                node.allocatedSize = e.allocatedSize
            default:
                flags.insert(.special)
            }
            node.flags = flags
            tree.nodes.append(node)
            index += 1
        }
    }

    private func entryName(_ batch: DirectoryBatch, _ e: RawEntry) -> String {
        batch.names.withUnsafeBufferPointer { buf in
            String(decoding: UnsafeBufferPointer(rebasing: buf[e.nameOffset ..< e.nameOffset + e.nameLength]), as: UTF8.self)
        }
    }

    /// Children always have a larger index than their parent, so one reverse pass sums every directory.
    private func aggregate() {
        tree.nodes.withUnsafeMutableBufferPointer { nodes in
            var i = nodes.count - 1
            while i > 0 {
                let n = nodes[i]
                let p = Int(n.parent)
                nodes[p].fileCount &+= n.fileCount
                if !n.flags.contains(.hardLinkDuplicate) {
                    nodes[p].logicalSize += n.logicalSize
                    nodes[p].allocatedSize += n.allocatedSize
                    if n.privateSize > 0 { nodes[p].privateSize += n.privateSize }
                }
                i -= 1
            }
        }
    }
}
