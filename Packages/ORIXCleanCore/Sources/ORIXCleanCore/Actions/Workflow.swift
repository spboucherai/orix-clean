// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Packages/ORIXCleanCore/Sources/ORIXCleanCore/Actions/Workflow.swift
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

// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/Actions/Workflow.swift
// Description: ORIX Clean Actions: reusable cleanup workflows. A removal step can only follow a review step.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation

public enum WorkflowStep: Codable, Sendable, Hashable {
    case scanFolder(path: String)
    case findDuplicates(minimumSizeMB: Int)
    case collectCaches
    case collectDeveloperData
    case collectDownloads(olderThanDays: Int)
    /// The user sees the cleanup preview and confirms. Cannot be skipped or automated.
    case review
    case moveToTrash
    case report

    public var title: String {
        switch self {
        case let .scanFolder(path): return L("Scan %@", path.abbreviatingHome)
        case let .findDuplicates(mb): return L("Find duplicates of %d MB or more", mb)
        case .collectCaches: return L("Analyze caches and logs")
        case .collectDeveloperData: return L("Analyze developer data")
        case let .collectDownloads(days): return L("Collect downloads older than %d days", days)
        case .review: return L("Review and confirm")
        case .moveToTrash: return L("Move to Trash")
        case .report: return L("Create report")
        }
    }
}

public enum WorkflowError: Error, Sendable, Equatable {
    case removalWithoutReview
    case duplicatesWithoutScan
    case empty
    case cancelled
}

public struct Workflow: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var steps: [WorkflowStep]
    public var builtIn: Bool

    public init(id: String = UUID().uuidString, name: String, steps: [WorkflowStep], builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.steps = steps
        self.builtIn = builtIn
    }

    /// A workflow is valid only if every removal step comes after a review step with no collection step in between.
    public func validate() throws {
        guard !steps.isEmpty else { throw WorkflowError.empty }
        var reviewed = false, scanned = false
        for step in steps {
            switch step {
            case .scanFolder: scanned = true; reviewed = false
            case .findDuplicates:
                if !scanned { throw WorkflowError.duplicatesWithoutScan }
                reviewed = false
            case .collectCaches, .collectDeveloperData, .collectDownloads: reviewed = false
            case .review: reviewed = true
            case .moveToTrash:
                if !reviewed { throw WorkflowError.removalWithoutReview }
                reviewed = false
            case .report: break
            }
        }
    }

    public static var builtIns: [Workflow] {
        [
            Workflow(id: "builtin.downloads-duplicates", name: L("Clean duplicate downloads"),
                     steps: [.scanFolder(path: NSHomeDirectory() + "/Downloads"), .findDuplicates(minimumSizeMB: 1), .review, .moveToTrash, .report], builtIn: true),
            Workflow(id: "builtin.developer", name: L("Developer cache cleanup"), steps: [.collectDeveloperData, .review, .moveToTrash, .report], builtIn: true),
            Workflow(id: "builtin.caches", name: L("Cache and log cleanup"), steps: [.collectCaches, .review, .moveToTrash, .report], builtIn: true),
            Workflow(id: "builtin.old-downloads", name: L("Old downloads review"), steps: [.collectDownloads(olderThanDays: 90), .review, .moveToTrash, .report], builtIn: true),
        ]
    }
}

public struct WorkflowEvent: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var step: Int
    public var message: String
    public var date = Date()
}

public struct WorkflowOutcome: Sendable {
    public var events: [WorkflowEvent]
    public var collected: [CleanupItem]
    public var report: DeletionReport?
    public var cancelled: Bool
    public var wantsReport: Bool
}

/// Asks the user. Returning nil cancels the workflow; nothing is removed.
public protocol WorkflowReviewer: Sendable {
    func review(_ plan: CleanupPlan) async -> (plan: CleanupPlan, authorization: CleanupAuthorization)?
}

public final class WorkflowRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelledFlag = false
    private var log: [WorkflowEvent] = []
    private let policy: SafetyPolicy
    private let trasher: Trasher
    private let home: String

    public init(policy: SafetyPolicy = SafetyPolicy(), trasher: Trasher = SystemTrasher(), home: String = NSHomeDirectory()) {
        self.policy = policy
        self.trasher = trasher
        self.home = home
    }

    public func cancel() { lock.lock(); cancelledFlag = true; lock.unlock() }
    public var events: [WorkflowEvent] { lock.lock(); defer { lock.unlock() }; return log }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledFlag }
    private func note(_ step: Int, _ message: String) { lock.lock(); log.append(WorkflowEvent(step: step, message: message)); lock.unlock() }

    public func run(_ workflow: Workflow, reviewer: WorkflowReviewer, runningBundleIDs: Set<String> = []) async throws -> WorkflowOutcome {
        try workflow.validate()
        var tree: ScanTree?
        var collected: [CleanupItem] = []
        var reviewed: (plan: CleanupPlan, authorization: CleanupAuthorization)?
        var report: DeletionReport?
        var wantsReport = false
        for (i, step) in workflow.steps.enumerated() {
            if isCancelled { return WorkflowOutcome(events: events, collected: collected, report: report, cancelled: true, wantsReport: false) }
            switch step {
            case let .scanFolder(path):
                let result = try await Self.background { try FileScanner(root: path).run() }
                tree = result.tree
                note(i, L("Scanned %@: %@ files, %@.", path.abbreviatingHome, ByteFormat.count(result.files), ByteFormat.string(result.tree[0].allocatedSize)))
            case let .findDuplicates(mb):
                guard let tree else { throw WorkflowError.duplicatesWithoutScan }
                var o = DuplicateOptions()
                o.minimumSize = Int64(mb) * 1_000_000
                let options = o
                let result = await Self.background { DuplicateFinder().run(tree: tree, options: options) }
                for g in result.groups {
                    // Keep the first path of each group; every other copy is proposed and verified against it before removal.
                    guard let keep = g.files.first else { continue }
                    for f in g.files.dropFirst() where f.hardLinkPaths.isEmpty {
                        var m = Measurement()
                        m.logical = g.logicalSize; m.allocated = f.allocatedSize; m.privateSize = f.privateSize; m.files = 1
                        m.modified = f.modified; m.fileID = f.fileID
                        collected.append(CleanupItem(path: f.path, category: .duplicate, risk: .review,
                                                     reason: L("Identical content (SHA-256) to %@.", keep.path.abbreviatingHome),
                                                     consequence: L("This copy goes to the Trash; the other copy stays where it is."),
                                                     measurement: m, verifyAgainst: keep.path))
                    }
                }
                note(i, L("Found %d duplicate groups.", result.groups.count))
            case .collectCaches:
                let h = home
                let items = await Self.background { CleanupCatalog.discover(.caches, home: h).filter { $0.risk == .low } }
                collected += items
                note(i, L("Found %d cache and log locations.", items.count))
            case .collectDeveloperData:
                let h = home
                let items = await Self.background { CleanupCatalog.discover(.developer, home: h).filter { $0.risk == .low } }
                collected += items
                note(i, L("Found %d developer data locations.", items.count))
            case let .collectDownloads(days):
                let h = home
                let entries = (try? await Self.background { try DownloadsAnalyzer.analyze(folder: h + "/Downloads") }) ?? []
                let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
                let items = entries.filter { ($0.added ?? $0.measurement.modified ?? Date()) < cutoff }.map { $0.cleanupItem() }
                collected += items
                note(i, L("Found %d downloads older than %d days.", items.count, days))
            case .review:
                let plan = CleanupPlan(items: collected)
                if plan.items.isEmpty { note(i, L("Nothing to review.")); reviewed = nil; continue }
                guard let answer = await reviewer.review(plan) else {
                    note(i, L("Review cancelled. Nothing was removed."))
                    return WorkflowOutcome(events: events, collected: collected, report: nil, cancelled: true, wantsReport: false)
                }
                reviewed = answer
                note(i, L("Confirmed %d items.", answer.plan.items.count))
            case .moveToTrash:
                guard let r = reviewed else { note(i, L("Nothing was confirmed; nothing removed.")); continue }
                let engine = DeletionEngine(policy: policy, trasher: trasher)
                let result = await Self.background { engine.execute(plan: r.plan, authorization: r.authorization, runningBundleIDs: runningBundleIDs) }
                report = result
                reviewed = nil
                collected = []
                note(i, L("Moved %d items to the Trash; %d skipped, %d failed.", result.count(.movedToTrash), result.count(.skipped), result.count(.failed)))
            case .report:
                wantsReport = true
                note(i, L("Report ready."))
            }
        }
        return WorkflowOutcome(events: events, collected: collected, report: report, cancelled: false, wantsReport: wantsReport)
    }

    static func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async { c.resume(with: Result { try work() }) }
        }
    }

    static func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { c in DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: work()) } }
    }
}
