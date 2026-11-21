// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/StorageAccounting/Queries.swift
// Description: Read-only queries over a ScanTree: largest files and folders, age filters, category breakdown.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation

public struct FileFilter: Sendable {
    public var minimumSize: Int64 = 0
    public var maximumSize: Int64 = .max
    public var modifiedBefore: Date?
    public var modifiedAfter: Date?
    public var categories: Set<FileCategory> = []
    public var extensions: Set<String> = []
    /// Case-insensitive substring of the name.
    public var nameContains = ""
    /// Restrict to this subtree.
    public var under: Int32 = 0
    /// Files inside packages (apps, photo libraries) are listed only on request: they are parts of a larger item.
    public var includePackageContents = false
    public var sizeKind: SizeKind = .allocated
    public init() {}
}

public struct FileHit: Sendable, Hashable, Identifiable {
    public var id: Int32 { node }
    public var node: Int32
    public var size: Int64
}

public struct CategoryTotal: Sendable, Hashable, Identifiable {
    public var id: FileCategory { category }
    public var category: FileCategory
    public var logical: Int64
    public var allocated: Int64
    public var files: Int
}

public enum TreeQuery {
    /// Marks every node that lies inside a package directory.
    static func packageMembership(_ tree: ScanTree) -> [Bool] {
        var inside = [Bool](repeating: false, count: tree.count)
        for i in 1 ..< max(1, tree.count) {
            let p = Int(tree.nodes[i].parent)
            inside[i] = inside[p] || tree.nodes[p].flags.contains(.package)
        }
        return inside
    }

    /// The `limit` largest regular files that pass the filter, largest first.
    public static func largestFiles(in tree: ScanTree, filter: FileFilter = FileFilter(), limit: Int = 500) -> [FileHit] {
        let inside = filter.includePackageContents ? [] : packageMembership(tree)
        let before = filter.modifiedBefore.map { Int64($0.timeIntervalSince1970) }
        let after = filter.modifiedAfter.map { Int64($0.timeIntervalSince1970) }
        let needle = filter.nameContains.lowercased()
        var heap = MinHeap(capacity: limit)
        tree.forEachFile(under: filter.under) { i, n in
            let size = filter.sizeKind == .allocated ? n.allocatedSize : n.logicalSize
            if size < filter.minimumSize || size > filter.maximumSize { return }
            if heap.isFull, size <= heap.minimum { return }
            if let before, n.modified >= before { return }
            if let after, n.modified < after { return }
            if !inside.isEmpty, inside[Int(i)] { return }
            if !filter.categories.isEmpty || !filter.extensions.isEmpty {
                let ext = tree.fileExtension(of: i)
                if !filter.extensions.isEmpty, !filter.extensions.contains(ext) { return }
                if !filter.categories.isEmpty, !filter.categories.contains(FileCategory.of(extension: ext)) { return }
            }
            if !needle.isEmpty, !tree.name(of: i).lowercased().contains(needle) { return }
            heap.insert(FileHit(node: i, size: size))
        }
        return heap.sortedDescending()
    }

    /// The largest directories (packages count as one item and are not descended into).
    public static func largestFolders(in tree: ScanTree, under: Int32 = 0, minimumSize: Int64 = 0, limit: Int = 200) -> [FileHit] {
        var heap = MinHeap(capacity: limit)
        var stack = [under]
        while let i = stack.popLast() {
            let n = tree.nodes[Int(i)]
            guard n.flags.contains(.directory), !n.flags.contains(.removed) else { continue }
            if i != under, n.allocatedSize >= minimumSize { heap.insert(FileHit(node: i, size: n.allocatedSize)) }
            if n.flags.contains(.package) { continue }
            for c in tree.children(of: i) where tree.nodes[Int(c)].flags.contains(.directory) { stack.append(c) }
        }
        return heap.sortedDescending()
    }

    public static func categories(in tree: ScanTree, under: Int32 = 0) -> [CategoryTotal] {
        var totals: [FileCategory: CategoryTotal] = [:]
        let inside = packageMembership(tree)
        tree.forEachFile(under: under) { i, n in
            if n.flags.contains(.hardLinkDuplicate) { return }
            var cat = FileCategory.of(extension: tree.fileExtension(of: i))
            if inside[Int(i)] {
                var p = n.parent
                while p > 0, !tree.nodes[Int(p)].flags.contains(.package) { p = tree.nodes[Int(p)].parent }
                let ext = tree.fileExtension(of: p)
                cat = ext == "app" ? .application : FileCategory.of(extension: ext)
            }
            var t = totals[cat] ?? CategoryTotal(category: cat, logical: 0, allocated: 0, files: 0)
            t.logical += n.logicalSize
            t.allocated += n.allocatedSize
            t.files += 1
            totals[cat] = t
        }
        return totals.values.sorted { $0.allocated > $1.allocated }
    }
}

/// Fixed-capacity min-heap that keeps the largest `capacity` hits.
struct MinHeap {
    private var items: [FileHit] = []
    private let capacity: Int
    init(capacity: Int) {
        self.capacity = max(1, capacity)
        items.reserveCapacity(self.capacity)
    }

    var isFull: Bool { items.count >= capacity }
    var minimum: Int64 { items.first?.size ?? 0 }

    mutating func insert(_ hit: FileHit) {
        if items.count < capacity {
            items.append(hit)
            var i = items.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                if items[p].size <= items[i].size { break }
                items.swapAt(p, i)
                i = p
            }
        } else if hit.size > items[0].size {
            items[0] = hit
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, items[l].size < items[m].size { m = l }
                if r < items.count, items[r].size < items[m].size { m = r }
                if m == i { break }
                items.swapAt(m, i)
                i = m
            }
        }
    }

    func sortedDescending() -> [FileHit] { items.sorted { $0.size > $1.size || ($0.size == $1.size && $0.node < $1.node) } }
}
