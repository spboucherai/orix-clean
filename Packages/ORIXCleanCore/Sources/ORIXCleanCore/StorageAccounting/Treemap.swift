// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Packages/ORIXCleanCore/Sources/ORIXCleanCore/StorageAccounting/Treemap.swift
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

// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/StorageAccounting/Treemap.swift
// Description: Squarified treemap layout with level-of-detail: only regions large enough to see are laid out.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import CoreGraphics
import Foundation

public struct TreemapCell: Sendable, Hashable {
    public var node: Int32
    public var rect: CGRect
    public var depth: Int
    /// Drawn as a filled block (a file, a package, or a folder too small to open up).
    public var isLeaf: Bool
    /// Stands for `aggregateCount` siblings that are too small to draw individually. `node` is their parent.
    public var aggregateCount: Int
    public var aggregateSize: Int64
}

public struct TreemapOptions: Sendable {
    public var sizeKind: SizeKind = .allocated
    /// A folder is opened up only if its rectangle is at least this wide and tall (points).
    public var minimumOpenSide: CGFloat = 26
    /// Children whose area would be under this many square points are merged into one "smaller items" cell.
    public var minimumArea: CGFloat = 14
    public var maximumDepth = 7
    public var header: CGFloat = 15
    public var padding: CGFloat = 1.5
    public var showPackageContents = false
    /// Only cells intersecting this rectangle are produced (viewport culling when zoomed).
    public var visible: CGRect?
    public init() {}
}

public enum Treemap {
    /// Lays out the subtree of `root` in `rect`. Areas are proportional to sizes within each parent.
    public static func layout(tree: ScanTree, root: Int32, in rect: CGRect, options: TreemapOptions = TreemapOptions()) -> [TreemapCell] {
        var cells: [TreemapCell] = []
        cells.reserveCapacity(2048)
        place(tree: tree, node: root, rect: rect, depth: 0, options: options, into: &cells)
        return cells
    }

    private static func place(tree: ScanTree, node: Int32, rect: CGRect, depth: Int, options o: TreemapOptions, into cells: inout [TreemapCell]) {
        if let v = o.visible, !v.intersects(rect) { return }
        let n = tree[node]
        let isOpenable = n.flags.contains(.directory) && n.childCount > 0 && (!n.flags.contains(.package) || o.showPackageContents || depth == 0)
            && depth < o.maximumDepth && rect.width >= o.minimumOpenSide && rect.height >= o.minimumOpenSide
        if !isOpenable {
            cells.append(TreemapCell(node: node, rect: rect, depth: depth, isLeaf: true, aggregateCount: 0, aggregateSize: 0))
            return
        }
        if depth > 0 { cells.append(TreemapCell(node: node, rect: rect, depth: depth, isLeaf: false, aggregateCount: 0, aggregateSize: 0)) }
        var inner = rect.insetBy(dx: o.padding, dy: o.padding)
        if depth > 0, rect.height > o.header * 2.2 {
            inner.origin.y += o.header
            inner.size.height -= o.header
        }
        guard inner.width > 2, inner.height > 2 else { return }
        var children: [(Int32, Int64)] = []
        children.reserveCapacity(Int(n.childCount))
        var total: Int64 = 0
        for c in tree.children(of: node) {
            let cn = tree[c]
            if cn.flags.contains(.removed) || cn.flags.contains(.hardLinkDuplicate) { continue }
            let s = o.sizeKind == .allocated ? cn.allocatedSize : cn.logicalSize
            if s > 0 { children.append((c, s)); total += s }
        }
        guard total > 0 else { return }
        children.sort { $0.1 > $1.1 }
        let scale = Double(inner.width * inner.height) / Double(total)
        // Merge the tail that would be invisible.
        var visibleCount = children.count
        var tail: Int64 = 0
        while visibleCount > 0, CGFloat(Double(children[visibleCount - 1].1) * scale) < o.minimumArea {
            tail += children[visibleCount - 1].1
            visibleCount -= 1
        }
        var areas = children[0 ..< visibleCount].map { Double($0.1) * scale }
        let tailCount = children.count - visibleCount
        if tailCount > 0 { areas.append(Double(tail) * scale) }
        let rects = squarify(areas: areas, in: inner)
        for i in 0 ..< visibleCount {
            place(tree: tree, node: children[i].0, rect: rects[i], depth: depth + 1, options: o, into: &cells)
        }
        if tailCount > 0, let r = rects.last, r.width >= 1, r.height >= 1, o.visible?.intersects(r) ?? true {
            cells.append(TreemapCell(node: node, rect: r, depth: depth + 1, isLeaf: true, aggregateCount: tailCount, aggregateSize: tail))
        }
    }

    /// Squarified treemap (Bruls, Huizing, van Wijk). `areas` must be sorted descending (the last may be an aggregate).
    public static func squarify(areas: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: areas.count)
        var free = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(free.width, free.height))
            guard side > 0 else { break }
            var end = start + 1
            var sum = areas[start]
            var worst = aspect(sum: sum, minArea: areas[start], maxArea: areas[start], side: side)
            while end < areas.count {
                let s = sum + areas[end]
                let w = aspect(sum: s, minArea: min(areas[end], areas[start ..< end].min() ?? areas[end]), maxArea: max(areas[start], areas[end]), side: side)
                if w > worst { break }
                sum = s; worst = w; end += 1
            }
            let thickness = sum / side
            var offset = 0.0
            let horizontal = free.width >= free.height   // row laid along the short side
            for i in start ..< end {
                let length = thickness > 0 ? areas[i] / thickness : 0
                if horizontal {
                    result[i] = CGRect(x: free.minX, y: free.minY + offset, width: thickness, height: length)
                } else {
                    result[i] = CGRect(x: free.minX + offset, y: free.minY, width: length, height: thickness)
                }
                offset += length
            }
            if horizontal {
                free = CGRect(x: free.minX + thickness, y: free.minY, width: max(0, free.width - thickness), height: free.height)
            } else {
                free = CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: max(0, free.height - thickness))
            }
            start = end
        }
        return result
    }

    private static func aspect(sum: Double, minArea: Double, maxArea: Double, side: Double) -> Double {
        guard sum > 0, minArea > 0 else { return .infinity }
        let s2 = sum * sum, w2 = side * side
        return max(w2 * maxArea / s2, s2 / (w2 * minArea))
    }
}
