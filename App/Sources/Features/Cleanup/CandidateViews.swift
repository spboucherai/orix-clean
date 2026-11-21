// ORIX Clean — App/Sources/Features/Cleanup/CandidateViews.swift
// Description: Candidate lists for caches, developer data and downloads. Every row states reason, risk and consequence.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import ORIXCleanCore
import SwiftUI

/// One candidate with its explanation. Used by every cleanup list.
struct CandidateRow: View {
    @Environment(AppModel.self) private var model
    var item: CleanupItem
    @State private var expanded = false

    var body: some View {
        let selected = model.isSelected(item.path)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: ORIX.Space.s) {
                Checkbox(isOn: selected, label: L("Select %@ for cleanup", item.name)) { model.toggle(item) }
                FileIcon(path: item.path, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(item.owner.map { $0 == item.name ? $0 : "\($0) — \(item.name)" } ?? item.name).lineLimit(1).truncationMode(.middle)
                        RiskBadge(risk: item.risk)
                        if !item.closeFirst.isEmpty, !model.runningBundleIDs.isDisjoint(with: item.closeFirst) {
                            Label(L("running"), systemImage: "play.circle").font(.caption).foregroundStyle(ORIX.Palette.review)
                                .help(L("The application is running. Quit it before cleaning this item."))
                        }
                    }
                    PathText(path: item.path)
                }
                Spacer(minLength: ORIX.Space.s)
                if let d = item.measurement.modified {
                    Text(ByteFormat.date(d)).font(.caption).foregroundStyle(ORIX.Palette.textSecondary).frame(width: 92, alignment: .trailing)
                }
                VStack(alignment: .trailing, spacing: 0) {
                    SizeText(bytes: item.measurement.allocated)
                    if item.measurement.files > 1 { Text(L("%@ files", ByteFormat.count(item.measurement.files))).font(.caption2.monospacedDigit()).foregroundStyle(ORIX.Palette.textTertiary) }
                }
                .frame(width: 100, alignment: .trailing)
                Button { withAnimation(.snappy(duration: 0.15)) { expanded.toggle() } } label: { Image(systemName: expanded ? "chevron.up" : "info.circle") }
                    .buttonStyle(.borderless).help(L("Why it is listed and what happens if you remove it"))
                    .accessibilityLabel(L("Details"))
            }
            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    detail(L("Why it is listed"), item.reason)
                    detail(L("If you remove it"), item.consequence)
                    if let r = item.regeneration { detail(L("Getting it back"), r) }
                    if let c = item.confidenceNote { detail(L("Certainty"), c) }
                    if item.measurement.incomplete { detail(L("Measurement"), L("Part of this item could not be read; its size is a lower bound.")) }
                    detail(L("Estimated recoverable"), item.measurement.recoverable.text)
                }
                .padding(.leading, 56).padding(.bottom, 4)
            }
        }
        .contextMenu { FileMenu(path: item.path) }
        .accessibilityElement(children: .contain)
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(k).font(.caption.weight(.semibold)).foregroundStyle(ORIX.Palette.textSecondary).frame(width: 150, alignment: .leading)
            Text(v).font(.caption).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

struct CandidateHeader: View {
    @Environment(AppModel.self) private var model
    var title: String
    var subtitle: String
    var items: [CleanupItem]
    var phase: TaskPhase
    var refresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: ORIX.Space.m) {
            SectionTitle(title: title, subtitle: subtitle)
            Spacer()
            if phase == .running { ProgressView().controlSize(.small) }
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.string(items.reduce(0) { $0 + $1.measurement.allocated })).font(.title3.weight(.semibold).monospacedDigit())
                Text(L("%@ items found", ByteFormat.count(items.count))).font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
            }
            Menu(L("Select")) {
                Button(L("All Low-Risk Items")) { model.select(items.filter { $0.risk == .low }) }
                Button(L("None")) { model.deselect(items.map(\.path)) }
            }.fixedSize()
            Button { refresh() } label: { Image(systemName: "arrow.clockwise") }.help(L("Measure again")).accessibilityLabel(L("Measure again")).disabled(phase == .running)
        }
        .padding(ORIX.Space.l)
    }
}

struct CachesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            CandidateHeader(title: L("Caches & Logs"),
                            subtitle: L("Recreatable data in documented locations. Apple system caches and caches that hold application state are never listed. Removing caches does not make a Mac faster; it returns space that applications may use again."),
                            items: model.caches, phase: model.cachesPhase) { model.loadCaches(force: true) }
            Divider()
            if model.caches.isEmpty, model.cachesPhase == .done {
                EmptyState(symbol: "internaldrive", title: L("Nothing to clean"), message: L("No cache or log location above 64 KB was found in the locations ORIX Clean knows."))
            } else {
                List {
                    ForEach([CleanupCategory.appCache, .browserCache, .logs, .temporary], id: \.self) { cat in
                        let list = model.caches.filter { $0.category == cat }
                        if !list.isEmpty {
                            Section("\(cat.title) · \(ByteFormat.string(list.reduce(0) { $0 + $1.measurement.allocated }))") {
                                ForEach(list) { CandidateRow(item: $0) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("caches.list")
            }
        }
        .onAppear { model.loadCaches() }
    }
}

struct DeveloperView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            CandidateHeader(title: L("Developer Cleanup Lab"),
                            subtitle: L("Build products, package caches and device support files, each with what it costs to regenerate. Simulators, runtimes and toolchains are never removed here."),
                            items: model.developer + model.buildArtifacts, phase: model.developerPhase) { model.loadDeveloper(force: true) }
            Divider()
            if model.developer.isEmpty, model.buildArtifacts.isEmpty, model.developerHints.isEmpty, model.developerPhase == .done {
                EmptyState(symbol: "hammer", title: L("No developer data found"), message: L("None of the known developer tool locations holds data on this Mac."))
            } else {
                List {
                    let owners = Dictionary(grouping: model.developer, by: { $0.owner ?? "" })
                    ForEach(owners.keys.sorted { (owners[$0]!.reduce(0) { $0 + $1.measurement.allocated }) > (owners[$1]!.reduce(0) { $0 + $1.measurement.allocated }) }, id: \.self) { owner in
                        Section("\(owner) · \(ByteFormat.string(owners[owner]!.reduce(0) { $0 + $1.measurement.allocated }))") {
                            ForEach(owners[owner]!) { CandidateRow(item: $0) }
                        }
                    }
                    if !model.buildArtifacts.isEmpty {
                        Section(L("Build folders in the scanned location · %@", ByteFormat.string(model.buildArtifacts.reduce(0) { $0 + $1.measurement.allocated }))) {
                            ForEach(model.buildArtifacts) { CandidateRow(item: $0) }
                        }
                    }
                    if !model.developerHints.isEmpty {
                        Section(L("Reported only — clean with the tool that owns it")) {
                            ForEach(model.developerHints) { h in
                                HStack(alignment: .top, spacing: ORIX.Space.s) {
                                    Image(systemName: "hand.raised").foregroundStyle(ORIX.Palette.textSecondary).frame(width: 22).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(h.owner)
                                        PathText(path: h.path + "/x")
                                        Text(h.guidance).font(.caption).foregroundStyle(ORIX.Palette.textSecondary).textSelection(.enabled)
                                    }
                                    Spacer()
                                    SizeText(bytes: h.measurement.allocated)
                                }
                                .contextMenu { FileMenu(path: h.path) }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("developer.list")
            }
        }
        .onAppear { model.loadDeveloper() }
    }
}

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var olderThan = 0

    var body: some View {
        let cutoff = Date().addingTimeInterval(-Double(olderThan) * 86400)
        let entries = model.downloads.filter { olderThan == 0 || ($0.added ?? $0.measurement.modified ?? Date()) < cutoff }
        VStack(spacing: 0) {
            CandidateHeader(title: L("Downloads & Archives"),
                            subtitle: L("Installers, disk images, archives and incomplete downloads in your Downloads folder. Everything here is “review required”: only you know what you still need."),
                            items: entries.map { $0.cleanupItem() }, phase: model.downloadsPhase) { model.loadDownloads(force: true) }
            HStack {
                Picker(L("Added"), selection: $olderThan) {
                    Text(L("Any time")).tag(0)
                    Text(L("More than 30 days ago")).tag(30)
                    Text(L("More than 90 days ago")).tag(90)
                    Text(L("More than 1 year ago")).tag(365)
                }.frame(width: 280)
                Spacer()
            }.padding(.horizontal, ORIX.Space.l).padding(.bottom, ORIX.Space.s)
            Divider()
            if case let .failed(message) = model.downloadsPhase {
                EmptyState(symbol: "lock", title: L("Downloads is not readable"), message: message)
            } else if entries.isEmpty, model.downloadsPhase == .done {
                EmptyState(symbol: "arrow.down.circle", title: L("Nothing here"), message: L("The Downloads folder has no item matching this filter."))
            } else {
                List {
                    ForEach(DownloadEntry.Kind.allCases, id: \.self) { kind in
                        let list = entries.filter { $0.kind == kind }
                        if !list.isEmpty {
                            Section("\(kind.title) · \(ByteFormat.string(list.reduce(0) { $0 + $1.measurement.allocated }))") {
                                ForEach(list) { CandidateRow(item: $0.cleanupItem()) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("downloads.list")
            }
        }
        .onAppear { model.loadDownloads() }
    }
}
