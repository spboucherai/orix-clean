// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/CleanupPlanner/DownloadsAndTrash.swift
// Description: Downloads folder analysis (installers, archives, partial downloads, old items) and Trash inventory.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation

public struct DownloadEntry: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case installer, diskImage, archive, partial, other
        public var title: String {
            switch self {
            case .installer: return L("Installers")
            case .diskImage: return L("Disk images")
            case .archive: return L("Archives")
            case .partial: return L("Incomplete downloads")
            case .other: return L("Other")
            }
        }
    }
    public var id: String { path }
    public var path: String
    public var kind: Kind
    public var category: FileCategory
    public var measurement: Measurement
    /// When the item arrived in the folder, when the filesystem recorded it.
    public var added: Date?
    /// A sibling with the same base name exists: the archive looks already extracted (not verified).
    public var extractedSibling: String?
    public var name: String { (path as NSString).lastPathComponent }

    public func cleanupItem(now: Date = Date()) -> CleanupItem {
        let reference = added ?? measurement.modified ?? now
        let days = Int(now.timeIntervalSince(reference) / 86400)
        var reason: String
        switch kind {
        case .installer: reason = L("Installer package in Downloads, added %d days ago.", days)
        case .diskImage: reason = L("Disk image in Downloads, added %d days ago.", days)
        case .archive: reason = L("Archive in Downloads, added %d days ago.", days)
        case .partial: reason = L("Incomplete download left by a browser, last modified %d days ago.", days)
        case .other: reason = L("Item in Downloads, added %d days ago.", days)
        }
        if let s = extractedSibling { reason += " " + L("An item named “%@” sits next to it; it may be the extracted content (not verified).", s) }
        return CleanupItem(path: path, category: kind == .archive || kind == .diskImage ? .archive : .download, risk: .review, reason: reason,
                           consequence: L("The file leaves Downloads. If you still need it you will have to download it again, if its source still exists."),
                           measurement: measurement, regeneration: L("Download again, if still available"))
    }
}

public enum DownloadsAnalyzer {
    static let partialExtensions: Set<String> = ["crdownload", "part", "download", "partial", "opdownload", "tmp"]

    /// Lists and measures the top-level items of a downloads folder. Blocking.
    public static func analyze(folder: String = NSHomeDirectory() + "/Downloads") throws -> [DownloadEntry] {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: folder)
        let visible = names.filter { !$0.hasPrefix(".") }
        let baseNames = Dictionary(grouping: visible, by: { ($0 as NSString).deletingPathExtension })
        var out: [DownloadEntry] = []
        for name in visible {
            let path = folder + "/" + name
            guard let m = Measure.item(path) else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            let cat = FileCategory.of(extension: ext)
            var kind: DownloadEntry.Kind = .other
            if partialExtensions.contains(ext) { kind = .partial } else if cat == .installer { kind = .installer }
            else if cat == .diskImage { kind = .diskImage } else if cat == .archive { kind = .archive }
            var sibling: String?
            if kind == .archive {
                var base = (name as NSString).deletingPathExtension
                if base.hasSuffix(".tar") { base = (base as NSString).deletingPathExtension }
                sibling = (baseNames[base] ?? []).first { $0 != name && !["zip", "gz", "tgz", "xz", "bz2", "7z", "rar"].contains(($0 as NSString).pathExtension.lowercased()) }
                if sibling == nil, visible.contains(base), base != name { sibling = base }
            }
            let added = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
            out.append(DownloadEntry(path: path, kind: kind, category: cat, measurement: m, added: added, extractedSibling: sibling))
        }
        return out.sorted { $0.measurement.allocated > $1.measurement.allocated }
    }
}

public struct TrashLocation: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var volumeName: String
    /// False when macOS refused to list it (Full Disk Access is required for the Trash).
    public var accessible: Bool
    public var items: [TrashItem]
    public var logical: Int64 { items.reduce(0) { $0 + $1.measurement.logical } }
    public var allocated: Int64 { items.reduce(0) { $0 + $1.measurement.allocated } }
    public var fileCount: Int { items.reduce(0) { $0 + $1.measurement.files } }
}

public struct TrashItem: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var measurement: Measurement
    public var name: String { (path as NSString).lastPathComponent }

    public var cleanupItem: CleanupItem {
        CleanupItem(path: path, category: .trash, risk: .review, reason: L("Item already in the Trash."),
                    consequence: L("Deleted for good. It cannot be put back from the Trash afterwards."), measurement: measurement,
                    regeneration: L("Not recoverable without a backup"))
    }
}

public enum TrashAnalyzer {
    /// Trash folders of the current user: the home Trash and one per mounted volume that has one.
    public static func locations(home: String = NSHomeDirectory(), volumes: [VolumeInfo] = Volumes.mounted()) -> [TrashLocation] {
        var candidates: [(String, String)] = [(home + "/.Trash", volumes.first { $0.isStartup }?.name ?? L("Startup volume"))]
        let uid = getuid()
        for v in volumes where !v.isStartup { candidates.append((v.path + "/.Trashes/\(uid)", v.name)) }
        var out: [TrashLocation] = []
        for (path, volume) in candidates {
            var st = stat()
            guard lstat(path, &st) == 0 else { continue }
            let fd = DirectoryReader.open(path)
            if fd < 0 {
                out.append(TrashLocation(path: path, volumeName: volume, accessible: false, items: []))
                continue
            }
            close(fd)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            let items = names.filter { $0 != ".DS_Store" }.compactMap { name -> TrashItem? in
                Measure.item(path + "/" + name).map { TrashItem(path: path + "/" + name, measurement: $0) }
            }.sorted { $0.measurement.allocated > $1.measurement.allocated }
            out.append(TrashLocation(path: path, volumeName: volume, accessible: true, items: items))
        }
        return out
    }
}

public enum Permissions {
    /// True when macOS lets this process read locations protected by Full Disk Access. Probed, never bypassed.
    public static func hasFullDiskAccess(home: String = NSHomeDirectory()) -> Bool {
        for probe in ["/Library/Application Support/com.apple.TCC/TCC.db", home + "/Library/Safari/Bookmarks.plist", home + "/Library/Mail"] {
            var st = stat()
            guard lstat(probe, &st) == 0 else { continue }
            let fd = open(probe, O_RDONLY | O_CLOEXEC)
            if fd >= 0 { close(fd); return true }
            if errno == EPERM || errno == EACCES { return false }
        }
        return false
    }

    public static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
