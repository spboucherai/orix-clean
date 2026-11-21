// ORIX Clean — App/Sources/Features/Cleanup/CleanupPreviewSheet.swift
// Description: Mandatory preview before any removal, and the per-item results afterwards with undo.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import ORIXCleanCore
import SwiftUI

struct CleanupPreviewSheet: View {
    @Environment(AppModel.self) private var model
    var request: PreviewRequest
    @State private var excluded: Set<String> = []
    @State private var acknowledged = false
    @State private var typed = ""

    private var plan: CleanupPlan { CleanupPlan(items: request.plan.items.filter { !excluded.contains($0.path) }) }

    var body: some View {
        let plan = plan
        let permanent = request.mode == .permanent
        let running = model.runningBundleIDs
        let busy = plan.items.filter { !running.isDisjoint(with: $0.closeFirst) }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ORIX.Space.s) {
                Text(permanent ? L("Delete permanently?") : L("Review before cleaning")).font(.title2.weight(.semibold))
                Text(permanent
                    ? L("These items are in the Trash. Deleting them is permanent and cannot be undone by ORIX Clean.")
                    : L("These exact items will be moved to the Trash. Space is reclaimed when you empty the Trash. Until then you can put them back."))
                    .font(.callout).foregroundStyle(ORIX.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: ORIX.Space.l) {
                    StatTile(title: L("Items"), value: ByteFormat.count(plan.items.count), detail: L("%@ files", ByteFormat.count(plan.fileCount)))
                    StatTile(title: L("Content size"), value: ByteFormat.string(plan.logicalSize), detail: L("Sum of file lengths"))
                    StatTile(title: L("Estimated recoverable"), value: plan.recoverable.text,
                             detail: plan.recoverable.isExact ? L("Allocated on disk") : L("Range: some files share storage (APFS)"))
                    StatTile(title: L("Highest risk"), value: plan.highestRisk.title, detail: nil)
                }
                .padding(.top, 4)
            }
            .padding(ORIX.Space.l)
            Divider()
            List {
                ForEach(plan.byRisk.indices, id: \.self) { i in
                    let (risk, items) = plan.byRisk[i]
                    Section {
                        ForEach(items) { item in row(item, busy: !running.isDisjoint(with: item.closeFirst)) }
                    } header: {
                        HStack { RiskBadge(risk: risk); Text(L("%@ items · %@", ByteFormat.count(items.count), ByteFormat.string(items.reduce(0) { $0 + $1.measurement.allocated }))) }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 260)
            .accessibilityIdentifier("preview.list")
            Divider()
            VStack(alignment: .leading, spacing: ORIX.Space.s) {
                if !busy.isEmpty {
                    InfoBanner(symbol: "play.circle", text: L("%d items belong to applications that are running. They will be left in place until you quit those applications.", busy.count))
                }
                if plan.highestRisk == .high {
                    Toggle(L("I have checked the high-risk items and want to remove them"), isOn: $acknowledged).toggleStyle(.checkbox)
                        .accessibilityIdentifier("preview.acknowledge")
                }
                if permanent {
                    HStack {
                        Text(L("Type DELETE to confirm:")).font(.callout)
                        TextField("DELETE", text: $typed).textFieldStyle(.roundedBorder).frame(width: 120).accessibilityIdentifier("preview.type")
                    }
                }
                HStack {
                    Text(L("Recovery: %@", permanent ? L("none after deletion, except from your own backups") : L("Put Back from the Trash, or Undo in the results")))
                        .font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                    Spacer()
                    Button(L("Cancel")) { model.cancelPreview(request) }.keyboardShortcut(.cancelAction).accessibilityIdentifier("preview.cancel")
                    Button(permanent ? L("Delete Permanently") : L("Move %@ Items to Trash", ByteFormat.count(plan.items.count))) {
                        model.confirm(request, plan: plan, highRiskAcknowledged: acknowledged)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(permanent ? ORIX.Palette.high : ORIX.Palette.accent)
                    .disabled(plan.items.isEmpty || (plan.highestRisk == .high && !acknowledged) || (permanent && typed != "DELETE"))
                    .accessibilityIdentifier("preview.confirm")
                }
            }
            .padding(ORIX.Space.l)
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 600, idealHeight: 680)
        .interactiveDismissDisabled()
    }

    private func row(_ item: CleanupItem, busy: Bool) -> some View {
        HStack(alignment: .top, spacing: ORIX.Space.s) {
            Checkbox(isOn: true, label: L("Keep %@ in this cleanup", item.name)) { excluded.insert(item.path) }
            FileIcon(path: item.path, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.path.abbreviatingHome).font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    if busy { Label(L("running"), systemImage: "play.circle").font(.caption).foregroundStyle(ORIX.Palette.review) }
                }
                Text(item.reason).font(.caption).foregroundStyle(ORIX.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                Text(item.consequence).font(.caption).foregroundStyle(ORIX.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                if let c = item.confidenceNote { Text(c).font(.caption.weight(.medium)).foregroundStyle(ORIX.Palette.review) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                SizeText(bytes: item.measurement.allocated)
                Text(item.category.title).font(.caption2).foregroundStyle(ORIX.Palette.textTertiary)
            }
        }
        .contextMenu { FileMenu(path: item.path) }
        .accessibilityElement(children: .combine)
    }
}

struct CleanupResultsSheet: View {
    @Environment(AppModel.self) private var model
    var reportID: UUID

    var body: some View {
        if let report = model.operations.first(where: { $0.id == reportID }) ?? model.lastReport {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: ORIX.Space.s) {
                    Text(report.cancelled ? L("Cleanup stopped") : L("Cleanup results")).font(.title2.weight(.semibold))
                    HStack(alignment: .top, spacing: ORIX.Space.l) {
                        ForEach(DeletionStatus.allCases, id: \.self) { s in
                            if report.count(s) > 0 { StatTile(title: s.title, value: ByteFormat.count(report.count(s)), detail: ByteFormat.string(report.allocated(s))) }
                        }
                    }
                    if report.mode == .moveToTrash, report.count(.movedToTrash) > 0 {
                        InfoBanner(symbol: "trash", text: L("%@ is now in the Trash and still occupies disk space. It is reclaimed when you empty the Trash.", ByteFormat.string(report.allocated(.movedToTrash))),
                                   actionTitle: L("Show Trash")) { model.showResults = false; model.section = .trash }
                    }
                    if let a = report.freeBefore, let b = report.freeAfter {
                        Text(L("Free space reported by macOS: %@ before, %@ after.", ByteFormat.string(a), ByteFormat.string(b)))
                            .font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
                    }
                }
                .padding(ORIX.Space.l)
                Divider()
                List(report.records) { r in
                    HStack(alignment: .top, spacing: ORIX.Space.s) {
                        Image(systemName: symbol(r.status)).foregroundStyle(color(r.status)).frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.path.abbreviatingHome).font(.callout).lineLimit(1).truncationMode(.middle)
                            Text("\(r.restored ? L("Put back") : r.status.title) — \(r.detail)").font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                        }
                        Spacer()
                        SizeText(bytes: r.allocatedSize)
                        if r.status == .movedToTrash, !r.restored, r.trashPath != nil {
                            Button(L("Put Back")) { model.restore(r, in: report) }.controlSize(.small)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                .listStyle(.inset)
                .frame(minHeight: 240)
                .accessibilityIdentifier("results.list")
                Divider()
                HStack {
                    Menu(L("Export Report")) {
                        ForEach(ReportFormat.allCases, id: \.self) { f in
                            Button(f.title) { model.export(Report(title: L("Cleanup results"), scope: L("%d items", report.records.count), sections: ReportBuilder.cleanupResults(report), appVersion: model.appVersion), format: f) }
                        }
                    }.fixedSize()
                    Spacer()
                    Button(L("Done")) { model.showResults = false }.keyboardShortcut(.defaultAction).accessibilityIdentifier("results.done")
                }
                .padding(ORIX.Space.l)
            }
            .frame(minWidth: 780, idealWidth: 860, minHeight: 520)
        }
    }

    private func symbol(_ s: DeletionStatus) -> String {
        switch s {
        case .movedToTrash: return "trash.circle.fill"
        case .permanentlyDeleted: return "xmark.bin.circle.fill"
        case .skipped: return "arrow.uturn.right.circle"
        case .failed: return "exclamationmark.octagon.fill"
        case .requiresManualAction: return "hand.raised.circle.fill"
        }
    }

    private func color(_ s: DeletionStatus) -> Color {
        switch s {
        case .movedToTrash: return ORIX.Palette.low
        case .permanentlyDeleted: return ORIX.Palette.accentSecondary
        case .skipped: return ORIX.Palette.textSecondary
        case .failed: return ORIX.Palette.high
        case .requiresManualAction: return ORIX.Palette.review
        }
    }
}
