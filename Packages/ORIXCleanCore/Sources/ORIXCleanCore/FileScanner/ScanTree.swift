// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Packages/ORIXCleanCore/Sources/ORIXCleanCore/FileScanner/ScanTree.swift
// Module           : ORIXCleanCore
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

// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/FileScanner/ScanTree.swift
// Description: Compact arena that holds the result of a scan (one fixed-size record per filesystem object).
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation

/// Facts about one filesystem object, as reported by the kernel during the scan.
public struct NodeFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let directory = NodeFlags(rawValue: 1 << 0)
    public static let symlink = NodeFlags(rawValue: 1 << 1)
    /// A directory presented by Finder as a single item (.app, .photoslibrary, …).
    public static let package = NodeFlags(rawValue: 1 << 2)
    /// The inode has more than one name (link count > 1).
    public static let hardLinked = NodeFlags(rawValue: 1 << 3)
    /// Another name of an inode that was already counted in this scan; contributes nothing to totals.
    public static let hardLinkDuplicate = NodeFlags(rawValue: 1 << 4)
    /// APFS reports that the file may share blocks with another file (clone or snapshot).
    public static let mayShareBlocks = NodeFlags(rawValue: 1 << 5)
    public static let sparse = NodeFlags(rawValue: 1 << 6)
    /// Content is not on this Mac (evicted iCloud / File Provider item). Reading it would download it.
    public static let dataless = NodeFlags(rawValue: 1 << 7)
    /// The directory could not be read (permission or privacy protection). Its size is unknown.
    public static let unreadable = NodeFlags(rawValue: 1 << 8)
    /// A mount point or a directory on another device; not traversed.
    public static let boundary = NodeFlags(rawValue: 1 << 9)
    /// Transparent filesystem compression (UF_COMPRESSED).
    public static let compressed = NodeFlags(rawValue: 1 << 10)
    /// Neither a regular file, a directory nor a symlink (socket, fifo, device).
    public static let special = NodeFlags(rawValue: 1 << 11)
    /// Removed by a cleanup after the scan; excluded from every listing.
    public static let removed = NodeFlags(rawValue: 1 << 12)
    /// Excluded by a scan option (not traversed).
    public static let skipped = NodeFlags(rawValue: 1 << 13)
}

/// One record of the arena. 64 bytes.
public struct ScanNode: Sendable {
    public var nameOffset: UInt32
    public var nameLength: UInt16
    public var flags: NodeFlags
    public var parent: Int32
    public var childStart: Int32
    public var childCount: Int32
    /// Number of regular files below (1 for a file).
    public var fileCount: UInt32
    /// Bytes of content (all forks). For a directory: sum over descendants, hard links counted once.
    public var logicalSize: Int64
    /// Bytes allocated on disk. For a directory: sum over descendants, hard links counted once.
    public var allocatedSize: Int64
    /// Bytes that the filesystem reports would be freed if this file alone were removed (APFS private size).
    /// -1 when the filesystem did not report it. For a directory: sum over descendants (a lower bound).
    public var privateSize: Int64
    /// Seconds since 1970.
    public var modified: Int64
    public var fileID: UInt64
}

/// Result tree of a scan. Built by `FileScanner`, then read-only except for `markRemoved`.
public final class ScanTree: @unchecked Sendable {
    public internal(set) var nodes: [ScanNode] = []
    var names: [UInt8] = []
    /// APFS clone identifier per node index, only for files that reported one.
    public internal(set) var cloneIDs: [Int32: UInt64] = [:]
    public let rootPath: String
    public let rootDevice: Int32

    init(rootPath: String, rootDevice: Int32) {
        self.rootPath = rootPath
        self.rootDevice = rootDevice
    }

    public var root: Int32 { 0 }
    public var count: Int { nodes.count }

    public subscript(index: Int32) -> ScanNode { nodes[Int(index)] }

    public func name(of index: Int32) -> String {
        let n = nodes[Int(index)]
        if index == 0 { return rootPath }
        return names.withUnsafeBufferPointer { buf in
            String(decoding: UnsafeBufferPointer(rebasing: buf[Int(n.nameOffset) ..< Int(n.nameOffset) + Int(n.nameLength)]), as: UTF8.self)
        }
    }

    /// Display name: last path component for the root.
    public func displayName(of index: Int32) -> String {
        if index == 0 {
            let last = (rootPath as NSString).lastPathComponent
            return last.isEmpty ? rootPath : last
        }
        return name(of: index)
    }

    public func path(of index: Int32) -> String {
        if index == 0 { return rootPath }
        var parts: [String] = []
        var i = index
        while i > 0 {
            parts.append(name(of: i))
            i = nodes[Int(i)].parent
        }
        var result = rootPath
        for part in parts.reversed() {
            if !result.hasSuffix("/") { result += "/" }
            result += part
        }
        return result
    }

    public func url(of index: Int32) -> URL {
        URL(fileURLWithPath: path(of: index), isDirectory: nodes[Int(index)].flags.contains(.directory))
    }

    public func fileExtension(of index: Int32) -> String {
        let n = nodes[Int(index)]
        guard index != 0, n.nameLength > 1 else { return "" }
        return names.withUnsafeBufferPointer { buf -> String in
            let start = Int(n.nameOffset), end = start + Int(n.nameLength)
            var i = end - 1
            while i > start {
                if buf[i] == 0x2E {
                    if end - i - 1 > 12 || end - i - 1 == 0 { return "" }
                    return String(decoding: UnsafeBufferPointer(rebasing: buf[(i + 1) ..< end]), as: UTF8.self).lowercased()
                }
                if buf[i] == 0x20 { return "" }
                i -= 1
            }
            return ""
        }
    }

    public func children(of index: Int32) -> Range<Int32> {
        let n = nodes[Int(index)]
        return n.childStart ..< (n.childStart + n.childCount)
    }

    /// Children that still exist, largest allocated size first.
    public func sortedChildren(of index: Int32, by key: SizeKind = .allocated) -> [Int32] {
        children(of: index)
            .filter { !nodes[Int($0)].flags.contains(.removed) }
            .sorted { size(of: $0, key) > size(of: $1, key) }
    }

    public func size(of index: Int32, _ kind: SizeKind) -> Int64 {
        let n = nodes[Int(index)]
        switch kind {
        case .logical: return n.logicalSize
        case .allocated: return n.allocatedSize
        }
    }

    public func isAncestor(_ a: Int32, of b: Int32) -> Bool {
        var i = nodes[Int(b)].parent
        while i >= 0 {
            if i == a { return true }
            if i == 0 { break }
            i = nodes[Int(i)].parent
        }
        return false
    }

    public func ancestors(of index: Int32) -> [Int32] {
        var out: [Int32] = []
        var i = index
        while i > 0 {
            i = nodes[Int(i)].parent
            out.append(i)
        }
        return out.reversed()
    }

    /// Finds the node for an absolute path below the root, if it was scanned.
    public func index(forPath path: String) -> Int32? {
        let rootStd = rootPath
        if path == rootStd { return 0 }
        let prefix = rootStd.hasSuffix("/") ? rootStd : rootStd + "/"
        guard path.hasPrefix(prefix) else { return nil }
        var current: Int32 = 0
        for part in path.dropFirst(prefix.count).split(separator: "/") {
            var found: Int32 = -1
            let wanted = Array(part.utf8)
            names.withUnsafeBufferPointer { buf in
                for c in children(of: current) {
                    let n = nodes[Int(c)]
                    if Int(n.nameLength) == wanted.count,
                       wanted.withUnsafeBufferPointer({ w in memcmp(buf.baseAddress! + Int(n.nameOffset), w.baseAddress!, wanted.count) == 0 }) {
                        found = c
                        break
                    }
                }
            }
            if found < 0 { return nil }
            current = found
        }
        return current
    }

    /// Marks a subtree as removed and subtracts its totals from every ancestor.
    /// Call only when no analysis is reading the tree.
    public func markRemoved(_ index: Int32) {
        guard index > 0, !nodes[Int(index)].flags.contains(.removed) else { return }
        let n = nodes[Int(index)]
        var stack = [index]
        while let i = stack.popLast() {
            nodes[Int(i)].flags.insert(.removed)
            let c = nodes[Int(i)]
            if c.childCount > 0 { stack.append(contentsOf: c.childStart ..< (c.childStart + c.childCount)) }
        }
        let counted = !n.flags.contains(.hardLinkDuplicate)
        var p = n.parent
        while p >= 0 {
            if counted {
                nodes[Int(p)].logicalSize -= n.logicalSize
                nodes[Int(p)].allocatedSize -= n.allocatedSize
                if n.privateSize > 0, nodes[Int(p)].privateSize > 0 { nodes[Int(p)].privateSize = max(0, nodes[Int(p)].privateSize - n.privateSize) }
            }
            nodes[Int(p)].fileCount = nodes[Int(p)].fileCount >= n.fileCount ? nodes[Int(p)].fileCount - n.fileCount : 0
            if p == 0 { break }
            p = nodes[Int(p)].parent
        }
    }

    /// Visits every existing regular file (not directories, symlinks or special files).
    public func forEachFile(under index: Int32 = 0, _ body: (Int32, ScanNode) -> Void) {
        if index == 0 {
            for i in 0 ..< nodes.count {
                let n = nodes[i]
                if n.flags.isDisjoint(with: [.directory, .symlink, .special, .removed]) { body(Int32(i), n) }
            }
            return
        }
        var stack = [index]
        while let i = stack.popLast() {
            let n = nodes[Int(i)]
            if n.flags.contains(.removed) { continue }
            if n.flags.contains(.directory) {
                if n.childCount > 0 { stack.append(contentsOf: n.childStart ..< (n.childStart + n.childCount)) }
            } else if n.flags.isDisjoint(with: [.symlink, .special]) {
                body(i, n)
            }
        }
    }
}

public enum SizeKind: String, Sendable, CaseIterable, Codable {
    /// Bytes of content.
    case logical
    /// Bytes allocated on disk.
    case allocated
}
