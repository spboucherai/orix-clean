// ORIX Clean — App/Sources/Features/Overview/OverviewView.swift
// Description: Dashboard: volumes, scan targets, measured breakdown by type, evidence-based recommendations.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Charts
import ORIXCleanCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("mapPalette") private var paletteName = MapPalette.orix.rawValue
    private var palette: MapPalette { MapPalette(rawValue: paletteName) ?? .orix }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ORIX.Space.l) {
                if !model.fullDiskAccess {
                    InfoBanner(symbol: "lock", text: L("Full Disk Access is off. Folders that macOS protects (Mail, Safari data, the Trash, other apps' containers) are not read and are missing from totals."),
                               actionTitle: L("Open Settings")) { NSWorkspace.shared.open(Permissions.fullDiskAccessSettingsURL) }
                }
                volumesCard
                scanCard
                if let scan = model.scan { breakdownCard(scan) }
                recommendationsCard
            }
            .padding(ORIX.Space.xl)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.loadCaches(); model.loadDeveloper(); model.loadDownloads(); model.loadTrash() }
    }

    private var volumesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: ORIX.Space.m) {
                SectionTitle(title: L("Volumes"), subtitle: L("Capacity and free space as reported by macOS right now."))
                ForEach(model.volumes) { v in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: v.isStartup ? "internaldrive.fill" : (v.isNetwork ? "network" : "externaldrive.fill")).foregroundStyle(ORIX.Palette.accent).accessibilityHidden(true)
                            Text(v.name).font(.headline)
                            Text(v.format.uppercased()).font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(ORIX.Palette.hairline, in: Capsule())
                            if v.isReadOnly { Text(L("Read-only")).font(.caption2).foregroundStyle(ORIX.Palette.textSecondary) }
                            Spacer()
                            Text(L("%@ free of %@", ByteFormat.string(v.available), ByteFormat.string(v.total))).font(.callout.monospacedDigit())
                            Button(L("Scan")) { model.startScan(path: v.path); model.section = .map }
                                .controlSize(.small).disabled(model.scanPhase == .running)
                                .accessibilityLabel(L("Scan %@", v.name))
                        }
                        ProportionBar(fraction: 1 - v.freeFraction, color: v.freeFraction < 0.1 ? ORIX.Palette.review : ORIX.Palette.accent, height: 8)
                        if v.purgeable > 500_000_000 {
                            Text(L("macOS reports %@ more that it can free on demand (purgeable: caches, local snapshots).", ByteFormat.string(v.purgeable)))
                                .font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    if v.id != model.volumes.last?.id { Divider() }
                }
            }
        }
    }

    private var scanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: ORIX.Space.m) {
                SectionTitle(title: L("Analyze storage"), subtitle: L("A scan reads names and sizes only. It never opens, changes or uploads your files."))
                HStack(spacing: ORIX.Space.m) {
                    scanButton(L("Home Folder"), "house", model.home, id: "overview.scanHome")
                    scanButton(L("Downloads"), "arrow.down.circle", model.home + "/Downloads", id: "overview.scanDownloads")
                    scanButton(L("Documents"), "doc", model.home + "/Documents", id: "overview.scanDocuments")
                    Button { model.chooseFolderAndScan() } label: { Label(L("Choose…"), systemImage: "folder") }.controlSize(.large)
                }
                if let scan = model.scan {
                    let _ = model.treeVersion
                    Divider()
                    HStack(alignment: .top, spacing: ORIX.Space.l) {
                        StatTile(title: L("Size on disk"), value: ByteFormat.string(scan.tree[0].allocatedSize), detail: scan.tree.rootPath.abbreviatingHome)
                        StatTile(title: L("Content size"), value: ByteFormat.string(scan.tree[0].logicalSize), detail: L("Sum of file lengths"))
                        StatTile(title: L("Files"), value: ByteFormat.count(Int(scan.tree[0].fileCount)), detail: L("%@ folders", ByteFormat.count(scan.directories)))
                        StatTile(title: L("Scan"), value: String(format: "%.1f s", scan.duration), detail: L("%@ items per second", ByteFormat.count(Int(scan.filesPerSecond))))
                    }
                    if !scan.issues.isEmpty {
                        let denied = scan.issues.filter { $0.kind == .permissionDenied }.count
                        InfoBanner(symbol: "eye.slash", text: L("%d folders could not be read (%d for lack of permission). Their content is not in these totals.", scan.issues.count, denied))
                    }
                }
            }
        }
    }

    private func scanButton(_ title: String, _ symbol: String, _ path: String, id: String) -> some View {
        Button { model.startScan(path: path); model.section = .map } label: { Label(title, systemImage: symbol) }
            .controlSize(.large).disabled(model.scanPhase == .running).accessibilityIdentifier(id)
    }

    private func breakdownCard(_ scan: ScanResult) -> some View {
        let _ = model.treeVersion
        let cats = TreeQuery.categories(in: scan.tree)
        let total = max(1, cats.reduce(0) { $0 + $1.allocated })
        return Card {
            VStack(alignment: .leading, spacing: ORIX.Space.m) {
                SectionTitle(title: L("What takes the space"), subtitle: L("Measured size on disk by file type in the scanned location."))
                Chart(cats) { c in
                    BarMark(x: .value(L("Size"), c.allocated))
                        .foregroundStyle(palette.swiftUIColor(c.category))
                }
                .chartXAxis(.hidden).chartLegend(.hidden).frame(height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .accessibilityHidden(true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: ORIX.Space.m)], alignment: .leading, spacing: ORIX.Space.s) {
                    ForEach(cats) { c in
                        HStack(spacing: 6) {
                            Image(systemName: c.category.symbol).foregroundStyle(palette.swiftUIColor(c.category)).frame(width: 18).accessibilityHidden(true)
                            Text(c.category.title)
                            Spacer()
                            Text(ByteFormat.string(c.allocated)).font(.callout.monospacedDigit())
                            Text(String(format: "%.0f%%", Double(c.allocated) / Double(total) * 100)).font(.caption.monospacedDigit())
                                .foregroundStyle(ORIX.Palette.textSecondary).frame(width: 36, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var recommendationsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: ORIX.Space.m) {
                SectionTitle(title: L("Recommendations"), subtitle: L("Each one states what was measured. None is produced without data."))
                if model.recommendations.isEmpty {
                    Text(L("Nothing stands out in what has been analyzed so far.")).font(.callout).foregroundStyle(ORIX.Palette.textSecondary)
                }
                ForEach(model.recommendations) { r in
                    HStack(alignment: .top, spacing: ORIX.Space.m) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(r.title).font(.headline); RiskBadge(risk: r.risk) }
                            Text(r.evidence).font(.callout)
                            Text(r.consequence).font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                        }
                        Spacer()
                        Button(r.suggestedAction) { model.section = AppSection(rawValue: r.destination.rawValue) ?? .overview }
                    }
                    .accessibilityElement(children: .contain)
                    if r.id != model.recommendations.last?.id { Divider() }
                }
            }
        }
    }
}
