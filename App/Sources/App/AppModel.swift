// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : App/Sources/App/AppModel.swift
// Description      : Observable application state: scan, analyses, cleanup
//                    selection, cleanup execution, history.
// Module           : App
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

import AppKit
import ORIXCleanCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, map, largeFiles, duplicates, similar, caches, developer, downloads, applications, trash, history, actions, reports
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("Overview")
        case .map: return L("Storage Map")
        case .largeFiles: return L("Large Files")
        case .duplicates: return L("Duplicates")
        case .similar: return L("Similar Images")
        case .caches: return L("Caches & Logs")
        case .developer: return L("Developer")
        case .downloads: return L("Downloads")
        case .applications: return L("Applications")
        case .trash: return L("Trash")
        case .history: return L("History")
        case .actions: return L("Actions")
        case .reports: return L("Reports")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .map: return "square.grid.3x3.square"
        case .largeFiles: return "doc.viewfinder"
        case .duplicates: return "doc.on.doc"
        case .similar: return "photo.on.rectangle.angled"
        case .caches: return "internaldrive"
        case .developer: return "hammer"
        case .downloads: return "arrow.down.circle"
        case .applications: return "square.grid.2x2"
        case .trash: return "trash"
        case .history: return "chart.xyaxis.line"
        case .actions: return "bolt"
        case .reports: return "doc.richtext"
        }
    }

    static let groups: [(String, [AppSection])] = [
        ("", [.overview]),
        ("Analyze", [.map, .largeFiles, .duplicates, .similar]),
        ("Clean", [.caches, .developer, .downloads, .applications, .trash]),
        ("Track", [.history, .actions, .reports]),
    ]
}

enum TaskPhase: Equatable {
    case idle, running, done
    case failed(String)
}

/// What the cleanup preview is asked to confirm.
struct PreviewRequest: Identifiable {
    let id = UUID()
    var plan: CleanupPlan
    var mode: DeletionMode
    /// Set when a workflow is waiting for the answer.
    var continuation: CheckedContinuation<(plan: CleanupPlan, authorization: CleanupAuthorization)?, Never>?
}

@Observable
final class AppModel {
    // MARK: Environment
    let home: String
    let store: HistoryStore?
    let launch: LaunchOptions
    var section: AppSection = .overview
    var volumes: [VolumeInfo] = []
    var fullDiskAccess = false

    // MARK: Scan
    var scanPhase: TaskPhase = .idle
    var scanProgress = ScanProgress()
    var scanPaused = false
    var scan: ScanResult?
    /// Bumped whenever the tree changes (new scan, items removed) so views recompute.
    var treeVersion = 0
    private var scanner: FileScanner?
    var mapFocus: Int32 = 0
    var mapSelection: Int32?

    // MARK: Analyses
    var duplicatePhase: TaskPhase = .idle
    var duplicateProgress = DuplicateProgress()
    var duplicates: DuplicateResult?
    var duplicateMinimumMB = 1
    private var duplicateFinder: DuplicateFinder?

    var similarPhase: TaskPhase = .idle
    var similarProgress = SimilarProgress()
    var similar: SimilarResult?
    var similarMode: SimilarImageOptions.Mode = .fast
    private var similarFinder: SimilarImageFinder?

    var cachesPhase: TaskPhase = .idle
    var caches: [CleanupItem] = []
    var developerPhase: TaskPhase = .idle
    var developer: [CleanupItem] = []
    var buildArtifacts: [CleanupItem] = []
    var developerHints: [CleanupCatalog.ManualHint] = []
    var downloadsPhase: TaskPhase = .idle
    var downloads: [DownloadEntry] = []
    var trashPhase: TaskPhase = .idle
    var trash: [TrashLocation] = []

    var appsPhase: TaskPhase = .idle
    var apps: [InstalledApp] = []
    var selectedApp: String?
    var associated: [String: [AssociatedFile]] = [:]
    var leftovers: [Leftover] = []
    var leftoversPhase: TaskPhase = .idle

    // MARK: Cleanup selection
    /// Items the user ticked anywhere in the app, keyed by path.
    var basket: [String: CleanupItem] = [:]
    var preview: PreviewRequest?
    var cleaning = false
    var cleanupDone = 0
    var cleanupTotal = 0
    var lastReport: DeletionReport?
    var showResults = false
    var operations: [DeletionReport] = []

    // MARK: History and recommendations
    var samples: [VolumeSample] = []
    var monitoringStart: Date?
    var watched: [String] = []
    var folderSamples: [String: [FolderSample]] = [:]
    var recommendations: [Recommendation] = []

    // MARK: Actions
    var workflows: [Workflow] = Workflow.builtIns
    var runningWorkflow: String?
    var workflowEvents: [WorkflowEvent] = []
    var lastExport: URL?
    var errorMessage: String?

    private var ticker: Timer?
    private var sampler: Timer?

    init(launch: LaunchOptions = LaunchOptions()) {
        self.launch = launch
        home = launch.home ?? NSHomeDirectory()
        PathDisplay.home = home
        store = try? HistoryStore(path: launch.storePath == "memory" ? nil : (launch.storePath ?? HistoryStore.defaultPath()))
        if let s = launch.section, let sec = AppSection(rawValue: s) { section = sec }
        refreshEnvironment()
        operations = store?.operations() ?? []
        workflows = Workflow.builtIns + (store?.documents(Workflow.self, kind: "workflow") ?? [])
        watched = store?.watched() ?? []
        for w in watched { folderSamples[w] = store?.folderSamples(path: w) ?? [] }
        sampler = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEnvironment() }
        }
    }

    // MARK: Environment

    var startupVolume: VolumeInfo? { volumes.first { $0.isStartup } }
    var sizeKind: SizeKind { SizeKind(rawValue: UserDefaults.standard.string(forKey: "sizeKind") ?? "") ?? .allocated }

    func refreshEnvironment() {
        volumes = Volumes.mounted()
        fullDiskAccess = Permissions.hasFullDiskAccess()
        if let store {
            for v in volumes where !v.isNetwork { store.record(volume: v) }
            if let v = startupVolume { samples = store.volumeSamples(volumeID: v.id, since: nil) }
            monitoringStart = store.monitoringStart()
        }
        evaluateRecommendations()
    }

    func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { c in DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: work()) } }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        if let scanner, scanPhase == .running { scanProgress = scanner.progress }
        if let duplicateFinder, duplicatePhase == .running { duplicateProgress = duplicateFinder.progress }
        if let similarFinder, similarPhase == .running { similarProgress = similarFinder.progress }
        if scanPhase != .running, duplicatePhase != .running, similarPhase != .running, !cleaning {
            ticker?.invalidate()
            ticker = nil
        }
    }

    var runningBundleIDs: Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }

    // MARK: Scan

    var tree: ScanTree? { scan?.tree }

    func startScan(path: String) {
        guard scanPhase != .running else { return }
        let options = path == "/" ? ScanOptions.startupVolume() : ScanOptions()
        let s = FileScanner(root: path, options: options)
        scanner = s
        scanPhase = .running
        scanPaused = false
        scanProgress = ScanProgress()
        startTicker()
        Task {
            let outcome: Result<ScanResult, Error> = await background { Result { try s.run() } }
            scanner = nil
            switch outcome {
            case let .success(r) where !r.cancelled:
                scan = r
                mapFocus = 0
                mapSelection = nil
                duplicates = nil; duplicatePhase = .idle
                similar = nil; similarPhase = .idle
                treeVersion += 1
                scanPhase = .done
                let t = r.tree
                buildArtifacts = await background { CleanupCatalog.buildArtifacts(in: t) }
                if watched.contains(r.tree.rootPath), let m = Measure.item(r.tree.rootPath) { recordFolder(r.tree.rootPath, m) }
                refreshEnvironment()
                if launch.autoAnalyze { findDuplicates(); findSimilar() }
            case .success:
                scanPhase = scan == nil ? .idle : .done
            case let .failure(e):
                switch e {
                case let ScanError.rootUnreadable(p, code): scanPhase = .failed(L("macOS did not allow reading %@ (%@).", p.abbreviatingHome, String(cString: strerror(code))))
                case let ScanError.rootNotFound(p): scanPhase = .failed(L("%@ does not exist.", p.abbreviatingHome))
                default: scanPhase = .failed(L("The folder could not be scanned."))
                }
            }
        }
    }

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Scan")
        panel.message = L("Choose a folder or a volume to analyze.")
        if panel.runModal() == .OK, let url = panel.url { startScan(path: url.path) }
    }

    func cancelScan() { scanner?.cancel() }
    func toggleScanPause() {
        guard let scanner else { return }
        if scanner.isPaused { scanner.resume() } else { scanner.pause() }
        scanPaused = scanner.isPaused
    }

    // MARK: Duplicates and similar images

    func findDuplicates() {
        guard let tree, duplicatePhase != .running else { return }
        let finder = DuplicateFinder()
        duplicateFinder = finder
        duplicatePhase = .running
        duplicateProgress = DuplicateProgress()
        startTicker()
        var o = DuplicateOptions()
        o.minimumSize = Int64(duplicateMinimumMB) * 1_000_000
        let options = o
        Task {
            let r = await background { finder.run(tree: tree, options: options) }
            duplicateFinder = nil
            if r.cancelled { duplicatePhase = duplicates == nil ? .idle : .done; return }
            duplicates = r
            duplicatePhase = .done
            evaluateRecommendations()
        }
    }

    func cancelDuplicates() { duplicateFinder?.cancel() }

    func findSimilar() {
        guard let tree, similarPhase != .running else { return }
        let finder = SimilarImageFinder()
        similarFinder = finder
        similarPhase = .running
        similarProgress = SimilarProgress()
        startTicker()
        var o = SimilarImageOptions()
        o.mode = similarMode
        let options = o
        Task {
            let r = await background { finder.run(tree: tree, options: options) }
            similarFinder = nil
            if r.cancelled { similarPhase = similar == nil ? .idle : .done; return }
            similar = r
            similarPhase = .done
        }
    }

    func cancelSimilar() { similarFinder?.cancel() }

    // MARK: Candidate discovery

    func loadCaches(force: Bool = false) {
        guard cachesPhase != .running, force || cachesPhase == .idle else { return }
        cachesPhase = .running
        let h = home
        let names = Dictionary(apps.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a })
        Task {
            let known = names.isEmpty ? await background { Dictionary(AppInventory.discover().map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a }) } : names
            caches = await background { CleanupCatalog.discover(.caches, home: h, appNames: known) }
            cachesPhase = .done
            evaluateRecommendations()
        }
    }

    func loadDeveloper(force: Bool = false) {
        guard developerPhase != .running, force || developerPhase == .idle else { return }
        developerPhase = .running
        let h = home
        Task {
            developer = await background { CleanupCatalog.discover(.developer, home: h) }
            developerHints = await background { CleanupCatalog.manualHints(home: h) }
            developerPhase = .done
            evaluateRecommendations()
        }
    }

    func loadDownloads(force: Bool = false) {
        guard downloadsPhase != .running, force || downloadsPhase == .idle else { return }
        downloadsPhase = .running
        let folder = home + "/Downloads"
        Task {
            let r: Result<[DownloadEntry], Error> = await background { Result { try DownloadsAnalyzer.analyze(folder: folder) } }
            switch r {
            case let .success(list): downloads = list; downloadsPhase = .done
            case .failure: downloads = []; downloadsPhase = .failed(L("macOS did not allow reading the Downloads folder. Allow it in System Settings > Privacy & Security > Files and Folders."))
            }
            evaluateRecommendations()
        }
    }

    func loadTrash(force: Bool = false) {
        guard trashPhase != .running, force || trashPhase == .idle else { return }
        trashPhase = .running
        let h = home
        let vols = launch.home == nil ? volumes : []
        Task {
            trash = await background { TrashAnalyzer.locations(home: h, volumes: vols) }
            trashPhase = .done
            evaluateRecommendations()
        }
    }

    func loadApps(force: Bool = false) {
        guard appsPhase != .running, force || appsPhase == .idle else { return }
        appsPhase = .running
        let dirs = launch.home == nil ? AppInventory.defaultDirectories : [home + "/Applications"]
        Task {
            apps = await background { AppInventory.discover(directories: dirs) }
            appsPhase = .done
            // Sizes, signatures and last-use dates arrive progressively.
            let list = apps
            for chunk in stride(from: 0, to: list.count, by: 8).map({ Array(list[$0 ..< min($0 + 8, list.count)]) }) {
                let measured = await background { chunk.map { AppInventory.measure($0) } }
                for m in measured { if let i = apps.firstIndex(where: { $0.path == m.path }) { apps[i] = m } }
            }
        }
    }

    func loadAssociated(for app: InstalledApp) {
        guard associated[app.path] == nil else { return }
        let h = home
        Task {
            let measured = app.signature == nil ? await background { AppInventory.measure(app) } : app
            associated[app.path] = await background { AppInventory.associatedFiles(for: measured, home: h) }
        }
    }

    func loadLeftovers() {
        guard leftoversPhase != .running else { return }
        leftoversPhase = .running
        let h = home
        let installed = apps
        let useLaunchServices = launch.home == nil
        Task {
            leftovers = await background {
                LeftoverFinder.find(installed: installed, home: h) { id in
                    useLaunchServices && LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil) != nil
                }
            }
            leftoversPhase = .done
        }
    }

    // MARK: Selection

    func isSelected(_ path: String) -> Bool { basket[path] != nil }

    func toggle(_ item: CleanupItem) {
        if basket[item.path] != nil { basket[item.path] = nil } else { basket[item.path] = item }
    }

    func select(_ items: [CleanupItem]) { for i in items { basket[i.path] = i } }
    func deselect(_ paths: [String]) { for p in paths { basket[p] = nil } }

    var basketPlan: CleanupPlan { CleanupPlan(items: Array(basket.values)) }

    /// Cleanup item for an arbitrary file or folder of the scanned tree (large files, storage map).
    func item(forNode node: Int32) -> CleanupItem? {
        guard let tree else { return nil }
        let n = tree[node]
        var m = Measurement()
        m.logical = n.logicalSize; m.allocated = n.allocatedSize; m.privateSize = scan?.sharingMeasured == true ? n.privateSize : -1
        m.files = Int(n.fileCount); m.isDirectory = n.flags.contains(.directory); m.fileID = n.fileID
        m.modified = Date(timeIntervalSince1970: TimeInterval(n.modified))
        return CleanupItem(path: tree.path(of: node), category: .largeFile, risk: .review,
                           reason: L("Selected by you in the storage analysis."),
                           consequence: L("The item goes to the Trash. ORIX Clean cannot know whether you still need it."),
                           measurement: m, regeneration: L("Not regenerated"))
    }

    /// Marks every copy of a duplicate group except `keep` for removal.
    func keepOnly(_ keep: DuplicateFile, in group: DuplicateGroup) {
        for f in group.files {
            if f.path == keep.path || !f.hardLinkPaths.isEmpty { basket[f.path] = nil; continue }
            var m = Measurement()
            m.logical = group.logicalSize; m.allocated = f.allocatedSize; m.privateSize = f.privateSize; m.files = 1; m.modified = f.modified; m.fileID = f.fileID
            var consequence = L("This copy goes to the Trash; “%@” stays.", keep.path.abbreviatingHome)
            if f.mayShareBlocks { consequence += " " + L("It may share its storage with other files, so less space than its size may be freed.") }
            basket[f.path] = CleanupItem(path: f.path, category: .duplicate, risk: .review,
                                         reason: L("Identical content (SHA-256 %@…) to the copy you keep.", String(group.digest.prefix(10))),
                                         consequence: consequence, measurement: m, verifyAgainst: keep.path)
        }
    }

    func clearGroup(_ group: DuplicateGroup) { for f in group.files { basket[f.path] = nil } }

    func toggleSimilar(_ image: SimilarImage, in group: SimilarGroup) {
        if basket[image.path] != nil { basket[image.path] = nil; return }
        // Never let a whole group be selected: one image always stays.
        let others = group.images.filter { $0.path != image.path }
        if others.allSatisfy({ basket[$0.path] != nil }) { errorMessage = L("At least one image of each group stays. Deselect another image first."); return }
        var m = Measurement()
        m.logical = image.logicalSize; m.allocated = image.allocatedSize; m.files = 1; m.modified = image.modified
        m.fileID = Measure.item(image.path)?.fileID ?? 0
        m.privateSize = Measure.privateSize(image.path) ?? -1
        basket[image.path] = CleanupItem(path: image.path, category: .similarImage, risk: .review,
                                         reason: L("Looks similar to %d other images (confidence %d%%). Similar is not identical.", others.count, Int(group.confidence * 100)),
                                         consequence: L("This image goes to the Trash. The others stay."), measurement: m)
    }

    // MARK: Cleanup

    func reviewBasket() {
        guard !basket.isEmpty else { return }
        preview = PreviewRequest(plan: basketPlan, mode: .moveToTrash)
    }

    func reviewEmptyTrash(_ items: [TrashItem]) {
        guard !items.isEmpty else { return }
        preview = PreviewRequest(plan: CleanupPlan(items: items.map(\.cleanupItem)), mode: .permanent)
    }

    /// Called by the preview when the user confirms. This is the only path that creates an authorization.
    func confirm(_ request: PreviewRequest, plan: CleanupPlan, highRiskAcknowledged: Bool) {
        let authorization = CleanupAuthorization(confirming: plan, highRiskAcknowledged: highRiskAcknowledged)
        preview = nil
        if let c = request.continuation {
            c.resume(returning: (plan, authorization))
            return
        }
        Task { await execute(plan: plan, authorization: authorization, mode: request.mode) }
    }

    func cancelPreview(_ request: PreviewRequest) {
        preview = nil
        request.continuation?.resume(returning: nil)
    }

    private var engine: DeletionEngine?

    func execute(plan: CleanupPlan, authorization: CleanupAuthorization, mode: DeletionMode) async {
        let e = DeletionEngine(policy: SafetyPolicy(home: home))
        engine = e
        cleaning = true
        cleanupTotal = plan.items.count
        cleanupDone = 0
        let running = runningBundleIDs
        let poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.cleanupDone = e.completed }
        }
        let report = await background { e.execute(plan: plan, authorization: authorization, mode: mode, runningBundleIDs: running) }
        poll.invalidate()
        engine = nil
        cleaning = false
        absorb(report)
        lastReport = report
        showResults = true
    }

    func cancelCleanup() { engine?.cancel() }

    /// Updates every list after a cleanup so nothing removed is still shown.
    func absorb(_ report: DeletionReport) {
        store?.save(report)
        operations.insert(report, at: 0)
        let gone = Set(report.records.filter { $0.status == .movedToTrash || $0.status == .permanentlyDeleted }.map(\.path))
        guard !gone.isEmpty else { return }
        for p in gone { basket[p] = nil }
        if let tree {
            for p in gone { if let i = tree.index(forPath: p) { tree.markRemoved(i) } }
            if let sel = mapSelection, tree[sel].flags.contains(.removed) { mapSelection = nil }
            while mapFocus != 0, tree[mapFocus].flags.contains(.removed) { mapFocus = tree[mapFocus].parent }
            treeVersion += 1
        }
        func alive(_ path: String) -> Bool { !gone.contains(path) && !gone.contains { path.hasPrefix($0 + "/") } }
        caches.removeAll { !alive($0.path) }
        developer.removeAll { !alive($0.path) }
        buildArtifacts.removeAll { !alive($0.path) }
        downloads.removeAll { !alive($0.path) }
        leftovers.removeAll { !alive($0.path) }
        apps.removeAll { !alive($0.path) }
        for (k, v) in associated { associated[k] = v.filter { alive($0.path) } }
        if var d = duplicates {
            d.groups = d.groups.compactMap { g in
                var g = g
                g.files.removeAll { !alive($0.path) }
                return g.files.count > 1 ? g : nil
            }
            duplicates = d
        }
        if var s = similar {
            s.groups = s.groups.compactMap { g in
                var g = g
                g.images.removeAll { !alive($0.path) }
                return g.images.count > 1 ? g : nil
            }
            similar = s
        }
        loadTrash(force: true)
        refreshEnvironment()
    }

    func restore(_ record: DeletionRecord, in report: DeletionReport) {
        let outcome = DeletionEngine(policy: SafetyPolicy(home: home)).restore(record)
        switch outcome {
        case .restored:
            var updated = report
            if let i = updated.records.firstIndex(where: { $0.path == record.path }) { updated.records[i].restored = true }
            store?.save(updated)
            if let i = operations.firstIndex(where: { $0.id == report.id }) { operations[i] = updated }
            if lastReport?.id == report.id { lastReport = updated }
            loadTrash(force: true)
        case .notInTrash: errorMessage = L("This item is no longer in the Trash, so it cannot be put back.")
        case .destinationOccupied: errorMessage = L("Another item now exists at the original location. Nothing was overwritten.")
        case let .failed(m): errorMessage = m
        }
    }

    // MARK: History

    func recordFolder(_ path: String, _ m: Measurement) {
        store?.record(folder: path, measurement: m)
        folderSamples[path] = store?.folderSamples(path: path) ?? []
    }

    func watch(_ path: String) {
        store?.watch(path)
        watched = store?.watched() ?? []
        Task {
            if let m = await background({ Measure.item(path) }) { recordFolder(path, m) }
        }
    }

    func unwatch(_ path: String) {
        store?.unwatch(path)
        watched = store?.watched() ?? []
    }

    func measureWatched() {
        for path in watched {
            Task { if let m = await background({ Measure.item(path) }) { recordFolder(path, m) } }
        }
    }

    func evaluateRecommendations() {
        var f = Findings()
        f.volumes = volumes
        f.duplicates = duplicates
        f.caches = cachesPhase == .done ? caches : nil
        f.developer = developerPhase == .done ? developer : nil
        f.downloads = downloadsPhase == .done ? downloads : nil
        f.trash = trashPhase == .done ? trash : nil
        if let v = startupVolume { f.history[v.id] = samples }
        recommendations = RecommendationEngine.evaluate(f)
    }

    // MARK: Actions

    func run(_ workflow: Workflow) {
        guard runningWorkflow == nil else { return }
        runningWorkflow = workflow.id
        workflowEvents = []
        let runner = WorkflowRunner(policy: SafetyPolicy(home: home), home: home)
        let reviewer = PreviewReviewer(model: self)
        let running = runningBundleIDs
        let poll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.workflowEvents = runner.events }
        }
        Task {
            do {
                let outcome = try await runner.run(workflow, reviewer: reviewer, runningBundleIDs: running)
                workflowEvents = outcome.events
                if let report = outcome.report {
                    absorb(report)
                    lastReport = report
                    showResults = true
                }
            } catch {
                errorMessage = L("The action could not run: %@", "\(error)")
            }
            poll.invalidate()
            runningWorkflow = nil
        }
    }

    func save(_ workflow: Workflow) {
        store?.saveDocument(workflow, kind: "workflow", id: workflow.id)
        workflows = Workflow.builtIns + (store?.documents(Workflow.self, kind: "workflow") ?? [])
    }

    func delete(_ workflow: Workflow) {
        store?.deleteDocument(kind: "workflow", id: workflow.id)
        workflows = Workflow.builtIns + (store?.documents(Workflow.self, kind: "workflow") ?? [])
    }

    // MARK: Reports

    var appVersion: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "") (\(i?["CFBundleVersion"] as? String ?? ""))"
    }

    func export(_ report: Report, format: ReportFormat) {
        let data = report.render(format)
        let name = report.title.replacingOccurrences(of: "/", with: "-") + " " + ISO8601DateFormatter().string(from: report.generated).prefix(10) + "." + format.fileExtension
        var url: URL?
        if let dir = launch.exportDirectory {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            if panel.runModal() == .OK { url = panel.url }
        }
        guard let url else { return }
        do {
            try data.write(to: url, options: .atomic)
            lastExport = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Bridges a workflow's review step to the cleanup preview sheet.
struct PreviewReviewer: WorkflowReviewer {
    let model: AppModel
    nonisolated init(model: AppModel) { self.model = model }
    nonisolated func review(_ plan: CleanupPlan) async -> (plan: CleanupPlan, authorization: CleanupAuthorization)? {
        await withCheckedContinuation { continuation in
            Task { @MainActor in model.preview = PreviewRequest(plan: plan, mode: .moveToTrash, continuation: continuation) }
        }
    }
}

/// Launch arguments used by UI tests, screenshots and benchmarks. None of them changes what the engines measure.
struct LaunchOptions {
    var home: String?
    var storePath: String?
    var scanRoot: String?
    var section: String?
    var autoAnalyze = false
    var exportDirectory: String?
    var appearance: String?
    var skipOnboarding = false
    var windowSize: CGSize?

    nonisolated init() {}

    static func fromProcess() -> LaunchOptions {
        let d = UserDefaults.standard
        var o = LaunchOptions()
        o.home = d.string(forKey: "ORIXHome")
        o.storePath = d.string(forKey: "ORIXStore")
        o.scanRoot = d.string(forKey: "ORIXScanRoot")
        o.section = d.string(forKey: "ORIXSection")
        o.autoAnalyze = d.bool(forKey: "ORIXAutoAnalyze")
        o.exportDirectory = d.string(forKey: "ORIXExportDir")
        o.appearance = d.string(forKey: "ORIXAppearance")
        o.skipOnboarding = d.bool(forKey: "ORIXSkipOnboarding")
        if let parts = d.string(forKey: "ORIXWindowSize")?.split(separator: "x").compactMap({ Double($0) }), parts.count == 2 {
            o.windowSize = CGSize(width: parts[0], height: parts[1])
        }
        return o
    }
}

#if DEBUG
extension AppModel {
    /// Debug builds only, and only on a substitute home folder (`-ORIXHome`): drives the real engines into a given state
    /// for screenshots. Not compiled into Release builds.
    func runDemo(_ name: String, confirm: Bool) async {
        guard launch.home != nil else { return }
        func wait(_ done: @escaping () -> Bool) async {
            for _ in 0 ..< 300 where !done() { try? await Task.sleep(for: .milliseconds(100)) }
        }
        switch name {
        case "duplicates":
            await wait { self.duplicatePhase == .done }
            for g in duplicates?.groups ?? [] { if let keep = g.files.first { keepOnly(keep, in: g) } }
            return
        case "uninstall":
            loadApps()
            await wait { self.appsPhase == .done && self.apps.allSatisfy { $0.measurement != nil } }
            guard let app = apps.first(where: { $0.name == "Sketcher" }) else { return }
            selectedApp = app.path
            loadAssociated(for: app)
            await wait { self.associated[app.path] != nil }
            if confirm || UserDefaults.standard.bool(forKey: "ORIXDemoPreview") {
                select(AppInventory.uninstallItems(app: app, files: (associated[app.path] ?? []).filter { $0.confidence == .identifier }))
            }
        default:
            loadCaches(); loadDeveloper()
            await wait { self.cachesPhase == .done && self.developerPhase == .done }
            select(caches.filter { $0.risk == .low } + developer.filter { $0.path.contains("DerivedData") })
        }
        guard !basket.isEmpty else { return }
        if confirm {
            let plan = basketPlan
            await execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false), mode: .moveToTrash)
        } else if UserDefaults.standard.bool(forKey: "ORIXDemoPreview") {
            reviewBasket()
        }
    }
}
#endif

