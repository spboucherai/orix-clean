// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/StorageAccounting/Support.swift
// Description: Shared helpers: localisation hook, byte formatting, file categories, quick measurements.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation

/// Localisation entry point for the whole product. Keys are the English strings.
public enum Localizer {
    nonisolated(unsafe) public static var bundle: Bundle = .main
    /// Overrides the system language (BCP 47, e.g. "fr-CA"); nil follows the system.
    nonisolated(unsafe) public static var locale: Locale = .autoupdatingCurrent
}

public func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Localizer.bundle.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, locale: Localizer.locale, arguments: args)
}

public enum ByteFormat {
    /// Locale-aware, decimal units (as Finder).
    public static func string(_ bytes: Int64) -> String {
        Int64(max(0, bytes)).formatted(.byteCount(style: .file).locale(Localizer.locale))
    }

    public static func count(_ n: Int) -> String { n.formatted(.number.locale(Localizer.locale)) }

    public static func date(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .none).locale(Localizer.locale))
    }

    public static func dateTime(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.locale))
    }
}

public enum FileCategory: String, Sendable, CaseIterable, Codable {
    case video, audio, image, archive, diskImage, installer, document, code, application, other

    public var title: String {
        switch self {
        case .video: return L("Video")
        case .audio: return L("Audio")
        case .image: return L("Images")
        case .archive: return L("Archives")
        case .diskImage: return L("Disk images")
        case .installer: return L("Installers")
        case .document: return L("Documents")
        case .code: return L("Code")
        case .application: return L("Applications")
        case .other: return L("Other")
        }
    }

    static let table: [String: FileCategory] = {
        var t: [String: FileCategory] = [:]
        func add(_ c: FileCategory, _ e: String) { for x in e.split(separator: " ") { t[String(x)] = c } }
        add(.video, "mp4 mov m4v mkv avi wmv flv webm mpg mpeg m2ts mts 3gp prores mxf braw r3d")
        add(.audio, "mp3 m4a aac wav aiff aif flac ogg opus wma alac caf m4b mid midi")
        add(.image, "jpg jpeg png heic heif tiff tif gif bmp webp raw cr2 cr3 nef arw dng orf rw2 psd psb svg ico icns avif jxl")
        add(.archive, "zip tar gz tgz bz2 tbz xz txz 7z rar zst lz4 cpio xar aar")
        add(.diskImage, "dmg iso img sparseimage sparsebundle toast cdr vmdk vdi qcow2 vhd vhdx")
        add(.installer, "pkg mpkg xip ipa apk msi exe deb rpm")
        add(.document, "pdf doc docx xls xlsx ppt pptx pages numbers key txt rtf rtfd md epub csv tex odt ods odp")
        add(.code, "swift m mm h c cc cpp hpp py js ts tsx jsx rb go rs java kt php sh json yml yaml xml html css sql o a dylib so class jar")
        add(.application, "app")
        return t
    }()

    public static func of(extension ext: String) -> FileCategory { table[ext] ?? .other }
}

/// Bytes a cleanup is expected to return to the volume. A range, because APFS can share blocks between files.
public struct RecoverableEstimate: Sendable, Hashable, Codable {
    /// Sum of the private sizes: what the filesystem says is used by these files only.
    public var minimum: Int64
    /// Sum of the allocated sizes: reached only when nothing is shared with files that stay.
    public var maximum: Int64

    public init(minimum: Int64, maximum: Int64) {
        self.minimum = min(minimum, maximum)
        self.maximum = maximum
    }

    public static let zero = RecoverableEstimate(minimum: 0, maximum: 0)
    public var isExact: Bool { minimum == maximum }

    public static func + (a: RecoverableEstimate, b: RecoverableEstimate) -> RecoverableEstimate {
        RecoverableEstimate(minimum: a.minimum + b.minimum, maximum: a.maximum + b.maximum)
    }

    public var text: String {
        isExact ? ByteFormat.string(maximum) : L("%@ to %@", ByteFormat.string(minimum), ByteFormat.string(maximum))
    }
}

public struct Measurement: Sendable, Hashable, Codable {
    public var logical: Int64 = 0
    public var allocated: Int64 = 0
    /// -1 when the filesystem does not report private sizes.
    public var privateSize: Int64 = -1
    public var files: Int = 0
    public var modified: Date?
    public var isDirectory = false
    public var fileID: UInt64 = 0
    /// True when part of the item could not be read; the sizes are then a lower bound.
    public var incomplete = false

    public var recoverable: RecoverableEstimate {
        RecoverableEstimate(minimum: privateSize >= 0 ? privateSize : allocated, maximum: allocated)
    }
}

public enum Measure {
    /// Measures a file or a whole directory. Returns nil when the item does not exist.
    public static func item(_ path: String) -> Measurement? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        var m = Measurement()
        m.fileID = UInt64(st.st_ino)
        m.modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        if (st.st_mode & S_IFMT) == S_IFDIR {
            m.isDirectory = true
            guard let r = try? FileScanner(root: path, options: { var o = ScanOptions(); o.workers = 2; return o }()).run() else {
                m.incomplete = true
                return m
            }
            let root = r.tree[0]
            m.logical = root.logicalSize
            m.allocated = root.allocatedSize
            m.privateSize = r.sharingMeasured ? root.privateSize : -1
            m.files = Int(root.fileCount)
            m.incomplete = !r.issues.isEmpty
            var latest = Int64(st.st_mtimespec.tv_sec)
            for n in r.tree.nodes where !n.flags.contains(.directory) { latest = max(latest, n.modified) }
            m.modified = Date(timeIntervalSince1970: TimeInterval(latest))
        } else {
            m.logical = Int64(st.st_size)
            m.allocated = Int64(st.st_blocks) * 512
            m.files = 1
            m.privateSize = privateSize(path) ?? -1
        }
        return m
    }

    /// APFS private size of one file, when the filesystem reports it.
    public static func privateSize(_ path: String) -> Int64? {
        var list = attrlist()
        list.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buffer = [UInt8](repeating: 0, count: 64)
        let rc = getattrlist(path, &list, &buffer, buffer.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        guard rc == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> Int64? in
            let returned = raw.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
            guard returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
            return raw.loadUnaligned(fromByteOffset: 4 + MemoryLayout<attribute_set_t>.size, as: Int64.self)
        }
    }
}

public extension String {
    /// Path with the home directory abbreviated to "~".
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
