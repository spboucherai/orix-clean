// ORIX Clean — App/Sources/Features/History/HistoryView.swift
// Description: Storage history: free space over time, watched folders, cleanup log. Only recorded samples are shown.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Charts
import ORIXCleanCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var range = 0
    @State private var openReport: DeletionReport?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ORIX.Space.l) {
                volumeCard
                watchedCard
                operationsCard
            }
            .padding(ORIX.Space.xl)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .sheet(item: $openReport) { r in
            CleanupResultsSheet(reportID: r.id).environment(model)
                .overlay(alignment: .topTrailing) { Button(L("Close")) { openReport = nil }.padding() }
        }
        .onAppear { model.refreshEnvironment() }
    }

    private var samples: [VolumeSample] {
        guard range > 0 else { return model.samples }
        let cutoff = Date().addingTimeInterval(-Double(range) * 86400)
        return model.samples.filter { $0.date >= cutoff }
    }

    private var volumeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: ORIX.Space.m) {
                HStack(alignment: .top) {
                    SectionTitle(title: L("Used space on %@", model.startupVolume?.name ?? ""),
                                 subtitle: model.monitoringStart.map { L("Recorded by ORIX Clean since %@, while the application is open. Nothing exists before that date.", ByteFormat.dateTime($0)) }
                                     ?? L("No sample recorded yet."))
                    Spacer()
                    Picker(L("Range"), selection: $range) {
                        Text(L("All")).tag(0); Text(L("24 hours")).tag(1); Text(L("7 days")).tag(7); Text(L("30 days")).tag(30)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
                }
                let s = samples
                if s.count < 2 {
                    Text(L("A trend needs at least two samples. One is recorded every 15 minutes while ORIX Clean is open, and after each scan and cleanup."))
                        .font(.callout).foregroundStyle(ORIX.Palette.textSecondary).frame(height: 120)
                } else {
                    let low = Double(s.map(\.used).min() ?? 0), high = Double(s.map(\.used).max() ?? 1)
                    let pad = max((high - low) * 0.15, 50_000_000)
                    Chart(s) { p in
                        AreaMark(x: .value(L("Date"), p.date), yStart: .value("", low - pad), yEnd: .value(L("Used"), Double(p.used)))
                            .foregroundStyle(LinearGradient(colors: [ORIX.Palette.accent.opacity(0.35), ORIX.Palette.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value(L("Date"), p.date), y: .value(L("Used"), Double(p.used)))
                            .foregroundStyle(ORIX.Palette.accent).lineStyle(StrokeStyle(lineWidth: 2))
                        if s.count <= 60 { PointMark(x: .value(L("Date"), p.date), y: .value(L("Used"), Double(p.used))).foregroundStyle(ORIX.Palette.accent).symbolSize(18) }
                    }
                    .chartYScale(domain: (low - pad) ... (high + pad))
                    .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(ByteFormat.string(Int64(d))) } } } }
                    .frame(height: 240)
                    .accessibilityLabel(L("Used space over time"))
                    .accessibilityValue(L("%d samples from %@ to %@", s.count, ByteFormat.string(Int64(low)), ByteFormat.string(Int64(high))))
                    HStack(alignment: .top, spacing: ORIX.Space.l) {
                        StatTile(title: L("Samples"), value: ByteFormat.count(s.count), detail: nil)
                        StatTile(title: L("Change over the period"), value: signed((s.last?.used ?? 0) - (s.first?.used ?? 0)), detail: nil)
                        if let slope = Trend.bytesPerDay(s) {
                            StatTile(title: L("Trend per day"), value: signed(Int64(slope)), detail: L("Least-squares fit of the samples"))
                        } else {
                            StatTile(title: L("Trend per day"), value: "—", detail: L("Needs 3 samples over at least 6 hours"))
                        }
                        StatTile(title: L("Free now"), value: ByteFormat.string(model.startupVolume?.available ?? 0), detail: nil)
                    }
                }
            }
        }
    }

    private func signed(_ v: Int64) -> String { (v < 0 ? "−" : "+") + ByteFormat.string(abs(v)) }

    private var watchedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: ORIX.Space.m) {
                HStack(alignment: .top) {
                    SectionTitle(title: L("Watched folders"), subtitle: L("Folders measured on demand so you can compare their size over time."))
                    Spacer()
                    Button(L("Measure Now")) { model.measureWatched() }.disabled(model.watched.isEmpty)
                    Button(L("Add Folder…")) {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK, let u = panel.url { model.watch(u.path) }
                    }
                }
                if model.watched.isEmpty { Text(L("No folder is watched.")).font(.callout).foregroundStyle(ORIX.Palette.textSecondary) }
                ForEach(model.watched, id: \.self) { path in
                    let list = model.folderSamples[path] ?? []
                    HStack(spacing: ORIX.Space.m) {
                        Image(systemName: "folder").foregroundStyle(ORIX.Palette.accentSecondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(path.abbreviatingHome).lineLimit(1).truncationMode(.middle)
                            Text(L("%d measurements", list.count) + (list.first.map { " · " + L("since %@", ByteFormat.date($0.date)) } ?? ""))
                                .font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                        }
                        Spacer()
                        if list.count > 1 {
                            Chart(list) { LineMark(x: .value("d", $0.date), y: .value("s", Double($0.allocated))).foregroundStyle(ORIX.Palette.accent) }
                                .chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 120, height: 26).accessibilityHidden(true)
                            Text(signed((list.last?.allocated ?? 0) - (list.first?.allocated ?? 0))).font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
                        }
                        if let last = list.last { SizeText(bytes: last.allocated) }
                        Button { model.unwatch(path) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel(L("Stop watching %@", path))
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private var operationsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: ORIX.Space.m) {
                SectionTitle(title: L("Cleanup history"), subtitle: L("Every cleanup run from ORIX Clean on this Mac, with its per-item outcome."))
                if model.operations.isEmpty { Text(L("No cleanup has been run yet.")).font(.callout).foregroundStyle(ORIX.Palette.textSecondary) }
                ForEach(model.operations.prefix(50)) { op in
                    HStack(spacing: ORIX.Space.m) {
                        Image(systemName: op.mode == .permanent ? "xmark.bin" : "trash").foregroundStyle(ORIX.Palette.textSecondary).frame(width: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ByteFormat.dateTime(op.started))
                            Text(summary(op)).font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                        }
                        Spacer()
                        SizeText(bytes: op.allocated(.movedToTrash) + op.allocated(.permanentlyDeleted))
                        Button(L("Details")) { openReport = op }.controlSize(.small)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func summary(_ op: DeletionReport) -> String {
        DeletionStatus.allCases.filter { op.count($0) > 0 }.map { "\(op.count($0)) \($0.title.lowercased())" }.joined(separator: " · ")
    }
}
