// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/FileScanner/DirectoryReader.swift
// Description: Reads one directory with getattrlistbulk(2): names, types, sizes and APFS sharing facts in a single pass.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation

/// One directory entry as returned by the kernel.
struct RawEntry {
    var nameOffset: Int
    var nameLength: Int
    var objType: UInt32 = 0
    var device: Int32 = 0
    var bsdFlags: UInt32 = 0
    var fileID: UInt64 = 0
    var modified: Int64 = 0
    var linkCount: UInt32 = 1
    var logicalSize: Int64 = 0
    var allocatedSize: Int64 = 0
    var privateSize: Int64 = -1
    var cloneID: UInt64 = 0
    var extFlags: UInt64 = 0
    var mountStatus: UInt32 = 0
    var error: Int32 = 0
}

/// Entries of one directory. Names are stored back to back in `names`.
struct DirectoryBatch {
    var entries: [RawEntry] = []
    var names: [UInt8] = []
}

enum DirectoryReader {
    static let vdir: UInt32 = 2, vreg: UInt32 = 1, vlnk: UInt32 = 5

    /// Opens a directory without following a final symlink. Handles paths longer than PATH_MAX by walking components.
    static func open(_ path: String) -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        let fd = Darwin.open(path, flags)
        if fd >= 0 || errno != ENAMETOOLONG { return fd }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if current < 0 { return -1 }
        let parts = path.split(separator: "/")
        for (i, part) in parts.enumerated() {
            // Like open(2), only the final component refuses symlinks.
            let next = openat(current, String(part), i == parts.count - 1 ? flags : O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            let saved = errno
            close(current)
            if next < 0 { errno = saved; return -1 }
            current = next
        }
        return current
    }

    /// Reads every entry of the open directory `fd`. Returns errno on failure (0 on success).
    /// `extended` asks for APFS private size, clone id and extended flags; filesystems that reject it are retried without.
    static func read(fd: Int32, extended: Bool, buffer: UnsafeMutableRawPointer, bufferSize: Int, into batch: inout DirectoryBatch) -> Int32 {
        var useExtended = extended
        while true {
            var list = attrlist()
            list.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
            list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_NAME)
                | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
                | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID)
            list.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
            list.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_TOTALSIZE) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
            var options: UInt64 = 0
            if useExtended {
                list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) | attrgroup_t(ATTR_CMNEXT_CLONEID) | attrgroup_t(ATTR_CMNEXT_EXT_FLAGS)
                options |= UInt64(FSOPT_ATTR_CMN_EXTENDED)
            }
            var first = true
            while true {
                let count = getattrlistbulk(fd, &list, buffer, bufferSize, options)
                if count < 0 {
                    let e = errno
                    if first, useExtended, e == EINVAL || e == ENOTSUP {
                        useExtended = false
                        break
                    }
                    return e
                }
                first = false
                if count == 0 { return 0 }
                var cursor = buffer
                for _ in 0 ..< count {
                    let length = Int(cursor.loadUnaligned(as: UInt32.self))
                    parse(entry: cursor, length: length, into: &batch)
                    cursor += length
                }
            }
        }
    }

    private static func parse(entry: UnsafeMutableRawPointer, length: Int, into batch: inout DirectoryBatch) {
        var p = UnsafeRawPointer(entry) + 4
        let returned = p.loadUnaligned(as: attribute_set_t.self)
        p += MemoryLayout<attribute_set_t>.size
        var e = RawEntry(nameOffset: batch.names.count, nameLength: 0)
        let common = returned.commonattr
        if common & attrgroup_t(ATTR_CMN_ERROR) != 0 {
            e.error = Int32(bitPattern: p.loadUnaligned(as: UInt32.self)); p += 4
        }
        if common & attrgroup_t(ATTR_CMN_NAME) != 0 {
            let ref = p.loadUnaligned(as: attrreference_t.self)
            let namePtr = p + Int(ref.attr_dataoffset)
            // attr_length includes the terminating NUL.
            let len = max(0, Int(ref.attr_length) - 1)
            batch.names.append(contentsOf: UnsafeRawBufferPointer(start: namePtr, count: len))
            e.nameLength = len
            p += MemoryLayout<attrreference_t>.size
        }
        if common & attrgroup_t(ATTR_CMN_DEVID) != 0 { e.device = p.loadUnaligned(as: Int32.self); p += 4 }
        if common & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 { e.objType = p.loadUnaligned(as: UInt32.self); p += 4 }
        if common & attrgroup_t(ATTR_CMN_MODTIME) != 0 { e.modified = Int64(p.loadUnaligned(as: Int.self)); p += 16 }
        if common & attrgroup_t(ATTR_CMN_FLAGS) != 0 { e.bsdFlags = p.loadUnaligned(as: UInt32.self); p += 4 }
        if common & attrgroup_t(ATTR_CMN_FILEID) != 0 { e.fileID = p.loadUnaligned(as: UInt64.self); p += 8 }
        if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 { e.mountStatus = p.loadUnaligned(as: UInt32.self); p += 4 }
        let file = returned.fileattr
        if file & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 { e.linkCount = p.loadUnaligned(as: UInt32.self); p += 4 }
        if file & attrgroup_t(ATTR_FILE_TOTALSIZE) != 0 { e.logicalSize = p.loadUnaligned(as: Int64.self); p += 8 }
        if file & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 { e.allocatedSize = p.loadUnaligned(as: Int64.self); p += 8 }
        let ext = returned.forkattr
        if ext & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 { e.privateSize = p.loadUnaligned(as: Int64.self); p += 8 }
        if ext & attrgroup_t(ATTR_CMNEXT_CLONEID) != 0 { e.cloneID = p.loadUnaligned(as: UInt64.self); p += 8 }
        if ext & attrgroup_t(ATTR_CMNEXT_EXT_FLAGS) != 0 { e.extFlags = p.loadUnaligned(as: UInt64.self); p += 8 }
        batch.entries.append(e)
    }
}
