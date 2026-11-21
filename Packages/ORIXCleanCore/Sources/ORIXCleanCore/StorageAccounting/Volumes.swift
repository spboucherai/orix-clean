// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Packages/ORIXCleanCore/Sources/ORIXCleanCore/StorageAccounting/Volumes.swift
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

// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/StorageAccounting/Volumes.swift
// Description: Mounted volume inventory with capacity figures reported by the system.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation

public struct VolumeInfo: Sendable, Hashable, Identifiable, Codable {
    public var id: String { uuid ?? path }
    public var path: String
    public var name: String
    public var uuid: String?
    public var format: String
    public var total: Int64
    /// Free blocks reported by the filesystem right now.
    public var available: Int64
    /// What the system says it can make available for important work (includes purgeable space).
    public var availableForImportantUsage: Int64
    public var isInternal: Bool
    public var isRemovable: Bool
    public var isReadOnly: Bool
    public var isStartup: Bool
    public var isNetwork: Bool

    public var used: Int64 { max(0, total - available) }
    /// Space the system could reclaim on demand (purgeable), as far as it reports it.
    public var purgeable: Int64 { max(0, availableForImportantUsage - available) }
    public var freeFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }

    /// Path to scan to see the user-visible content of this volume.
    public var scanRoot: String { path }
}

public enum Volumes {
    public static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeUUIDStringKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsRemovableKey,
                                      .volumeIsReadOnlyKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { info(for: $0) }.sorted { $0.isStartup && !$1.isStartup || ($0.isStartup == $1.isStartup && $0.name < $1.name) }
    }

    public static func info(for url: URL) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeUUIDStringKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsRemovableKey,
                                         .volumeIsReadOnlyKey, .volumeIsLocalKey]
        guard let v = try? url.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity, total > 0 else { return nil }
        var fs = statfs()
        var format = ""
        var readOnly = v.volumeIsReadOnly ?? false
        if statfs(url.path, &fs) == 0 {
            format = withUnsafeBytes(of: fs.f_fstypename) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
            // The startup volume is a sealed read-only snapshot; what matters to the user is the writable Data volume.
            if url.path == "/" { readOnly = false } else if fs.f_flags & UInt32(MNT_RDONLY) != 0 { readOnly = true }
        }
        let available = Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeInfo(path: url.path, name: v.volumeName ?? url.lastPathComponent, uuid: v.volumeUUIDString, format: format,
                          total: Int64(total), available: available,
                          availableForImportantUsage: max(available, v.volumeAvailableCapacityForImportantUsage ?? 0),
                          isInternal: v.volumeIsInternal ?? false, isRemovable: v.volumeIsRemovable ?? false, isReadOnly: readOnly,
                          isStartup: url.path == "/", isNetwork: !(v.volumeIsLocal ?? true))
    }

    public static func containing(_ path: String) -> VolumeInfo? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let mount = withUnsafeBytes(of: fs.f_mntonname) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        let shown = mount == "/System/Volumes/Data" ? "/" : mount
        return info(for: URL(fileURLWithPath: shown))
    }
}
