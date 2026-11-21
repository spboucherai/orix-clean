// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Packages/ORIXCleanCore/Sources/ORIXCleanCore/Intelligence/Recommendations.swift
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

// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/Intelligence/Recommendations.swift
// Description: Evidence-based recommendations computed only from measured findings.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation

public struct Recommendation: Sendable, Hashable, Identifiable {
    public enum Destination: String, Sendable { case duplicates, developer, caches, downloads, trash, largeFiles, history, applications }
    public var id: String
    public var title: String
    /// What was measured, in a sentence.
    public var evidence: String
    public var paths: [String]
    public var measuredSize: Int64
    public var risk: Risk
    public var consequence: String
    public var suggestedAction: String
    public var destination: Destination
}

/// Everything the engine may look at. Nil means "not analysed yet": no recommendation is produced from absent data.
public struct Findings: Sendable {
    public var volumes: [VolumeInfo] = []
    public var duplicates: DuplicateResult?
    public var caches: [CleanupItem]?
    public var developer: [CleanupItem]?
    public var downloads: [DownloadEntry]?
    public var trash: [TrashLocation]?
    public var history: [String: [VolumeSample]] = [:]
    public var now = Date()
    public init() {}
}

public enum RecommendationEngine {
    public static let lowSpaceFraction = 0.10
    public static let gb: Int64 = 1_000_000_000

    public static func evaluate(_ f: Findings) -> [Recommendation] {
        var out: [Recommendation] = []
        for v in f.volumes where !v.isReadOnly && v.total > 0 && v.freeFraction < lowSpaceFraction {
            out.append(Recommendation(
                id: "low-space-" + v.id, title: L("%@ is running low on free space", v.name),
                evidence: L("%@ free of %@ (%d%%).", ByteFormat.string(v.available), ByteFormat.string(v.total), Int((v.freeFraction * 100).rounded())),
                paths: [v.path], measuredSize: v.available, risk: .low,
                consequence: L("macOS needs free space for updates, swap and snapshots; very low space can cause failed saves."),
                suggestedAction: L("Review the largest files and folders."), destination: .largeFiles))
        }
        for (id, samples) in f.history {
            guard let slope = Trend.bytesPerDay(samples), slope > Double(gb) / 2, let v = f.volumes.first(where: { $0.id == id }), v.available > 0 else { continue }
            let days = Double(v.available) / slope
            guard days < 60, let first = samples.first else { continue }
            out.append(Recommendation(
                id: "growth-" + id, title: L("%@ is filling up", v.name),
                evidence: L("Used space grew by about %@ per day since %@ (%d samples). At this rate the free space lasts about %d days.",
                            ByteFormat.string(Int64(slope)), ByteFormat.date(first.date), samples.count, Int(days)),
                paths: [v.path], measuredSize: Int64(slope), risk: .low,
                consequence: L("A projection from past samples, not a forecast: growth may stop or accelerate."),
                suggestedAction: L("Open Storage History to see when the growth started."), destination: .history))
        }
        if let d = f.duplicates, d.redundantLogical >= 200_000_000 {
            let top = d.groups.prefix(5).flatMap { $0.files.map(\.path) }
            let shared = d.groups.filter(\.sharesStorage).count
            var evidence = L("%d groups of identical files; the extra copies hold %@ of content.", d.groups.count, ByteFormat.string(d.redundantLogical))
            if shared > 0 { evidence += " " + L("%d groups share storage on disk (APFS clones): removing those frees less than their size.", shared) }
            out.append(Recommendation(id: "duplicates", title: L("Identical files take up space"), evidence: evidence, paths: Array(top.prefix(10)),
                                      measuredSize: d.redundantLogical, risk: .review,
                                      consequence: L("One copy of each file stays. You choose which."), suggestedAction: L("Review the duplicate groups."),
                                      destination: .duplicates))
        }
        if let dev = f.developer {
            let derived = dev.filter { $0.path.contains("/Developer/Xcode/DerivedData/") }
            let size = derived.reduce(0) { $0 + $1.measurement.allocated }
            if size >= 5 * gb {
                out.append(Recommendation(id: "deriveddata", title: L("Xcode DerivedData is large"),
                                          evidence: L("%d project folders in DerivedData use %@.", derived.count, ByteFormat.string(size)),
                                          paths: derived.prefix(10).map(\.path), measuredSize: size, risk: .low,
                                          consequence: L("The next build of each removed project is a full build."),
                                          suggestedAction: L("Review developer data."), destination: .developer))
            }
            let archives = dev.filter { $0.path.contains("/Developer/Xcode/Archives/") }
            let old = archives.filter { ($0.measurement.modified ?? f.now) < f.now.addingTimeInterval(-180 * 86400) }
            let oldSize = old.reduce(0) { $0 + $1.measurement.allocated }
            if oldSize >= gb {
                out.append(Recommendation(id: "old-archives", title: L("Old Xcode archives"),
                                          evidence: L("%d archive folders older than 180 days use %@.", old.count, ByteFormat.string(oldSize)),
                                          paths: old.prefix(10).map(\.path), measuredSize: oldSize, risk: .review,
                                          consequence: L("Crash reports of those builds can no longer be symbolicated from this Mac."),
                                          suggestedAction: L("Review developer data."), destination: .developer))
            }
        }
        if let caches = f.caches {
            let caches = caches.filter { $0.risk == .low }
            let size = caches.reduce(0) { $0 + $1.measurement.allocated }
            if size >= 2 * gb {
                out.append(Recommendation(id: "caches", title: L("Application caches are large"),
                                          evidence: L("%d cache and log locations use %@.", caches.count, ByteFormat.string(size)),
                                          paths: caches.prefix(10).map(\.path), measuredSize: size, risk: .low,
                                          consequence: L("Applications rebuild their caches as needed, so part of this space is used again over time."),
                                          suggestedAction: L("Review caches."), destination: .caches))
            }
        }
        if let downloads = f.downloads {
            let cutoff = f.now.addingTimeInterval(-90 * 86400)
            let old = downloads.filter { [.installer, .diskImage].contains($0.kind) && ($0.added ?? $0.measurement.modified ?? f.now) < cutoff }
            let size = old.reduce(0) { $0 + $1.measurement.allocated }
            if size >= 500_000_000 {
                out.append(Recommendation(id: "old-installers", title: L("Downloads contains old installers"),
                                          evidence: L("%d installers and disk images added more than 90 days ago use %@.", old.count, ByteFormat.string(size)),
                                          paths: old.prefix(10).map(\.path), measuredSize: size, risk: .review,
                                          consequence: L("Installers can usually be downloaded again, but not always the same version."),
                                          suggestedAction: L("Review Downloads."), destination: .downloads))
            }
            let partial = downloads.filter { $0.kind == .partial }
            let psize = partial.reduce(0) { $0 + $1.measurement.allocated }
            if psize >= 100_000_000 {
                out.append(Recommendation(id: "partial-downloads", title: L("Incomplete downloads"),
                                          evidence: L("%d incomplete downloads use %@.", partial.count, ByteFormat.string(psize)),
                                          paths: partial.map(\.path), measuredSize: psize, risk: .review,
                                          consequence: L("A download in progress would be interrupted."), suggestedAction: L("Review Downloads."), destination: .downloads))
            }
        }
        if let trash = f.trash {
            let size = trash.reduce(0) { $0 + $1.allocated }
            let count = trash.reduce(0) { $0 + $1.items.count }
            if size >= gb {
                out.append(Recommendation(id: "trash", title: L("The Trash holds a lot of data"),
                                          evidence: L("%d items in the Trash use %@.", count, ByteFormat.string(size)),
                                          paths: trash.map(\.path), measuredSize: size, risk: .review,
                                          consequence: L("Emptying the Trash is permanent."), suggestedAction: L("Review the Trash."), destination: .trash))
            }
        }
        return out.sorted { $0.measuredSize > $1.measuredSize }
    }
}
