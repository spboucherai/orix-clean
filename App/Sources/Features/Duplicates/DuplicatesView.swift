// ORIX Clean — App/Sources/Features/Duplicates/DuplicatesView.swift
// Description: Exact duplicate groups with per-group choice of the copy to keep.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import ORIXCleanCore
import SwiftUI

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []

    var body: some View {
        @Bindable var model = model
        if model.tree == nil {
            EmptyState(symbol: "doc.on.doc", title: L("No scan yet"), message: L("Scan a folder first. Duplicates are searched inside the scanned location."),
                       actionTitle: L("Scan Home Folder")) { model.startScan(path: model.home) }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: ORIX.Space.m) {
                    Picker(L("Minimum size"), selection: $model.duplicateMinimumMB) {
                        Text(L("Any size")).tag(0)
                        ForEach([1, 10, 100, 1000], id: \.self) { Text(ByteFormat.string(Int64($0) * 1_000_000)).tag($0) }
                    }.frame(width: 240)
                    Button(model.duplicates == nil ? L("Find Duplicates") : L("Search Again")) { model.findDuplicates() }
                        .buttonStyle(.borderedProminent).disabled(model.duplicatePhase == .running).accessibilityIdentifier("duplicates.find")
                    Spacer()
                    if let d = model.duplicates {
                        Text(L("%@ groups · %@ in extra copies", ByteFormat.count(d.groups.count), ByteFormat.string(d.redundantLogical)))
                            .font(.callout.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
                    }
                }
                .padding(.horizontal, ORIX.Space.m).padding(.vertical, ORIX.Space.s).background(.bar)
                Divider()
                if model.duplicatePhase == .running {
                    let p = model.duplicateProgress
                    ProgressLine(title: p.stage == .hashing ? L("Comparing content (SHA-256)…") : L("Narrowing candidates…"),
                                 detail: L("%@ of %@ files · %@ read", ByteFormat.count(p.filesDone), ByteFormat.count(p.filesTotal), ByteFormat.string(p.bytesHashed)),
                                 fraction: p.filesTotal > 0 ? Double(p.filesDone) / Double(p.filesTotal) : nil) { model.cancelDuplicates() }
                        .padding(ORIX.Space.m)
                }
                if let d = model.duplicates {
                    if d.groups.isEmpty {
                        EmptyState(symbol: "checkmark.seal", title: L("No duplicates found"),
                                   message: L("%@ files of the same size were compared; none has identical content.", ByteFormat.count(d.candidates)))
                    } else {
                        list(d)
                    }
                } else if model.duplicatePhase != .running {
                    EmptyState(symbol: "doc.on.doc", title: L("Find identical files"),
                               message: L("Files are grouped by size, then by a sampled hash, then by a full SHA-256 of their content. Before a copy is removed it is compared byte for byte with the copy you keep."),
                               actionTitle: L("Find Duplicates")) { model.findDuplicates() }
                }
            }
        }
    }

    private func list(_ d: DuplicateResult) -> some View {
        List {
            if !d.unreadable.isEmpty {
                InfoBanner(symbol: "eye.slash", text: L("%d files could not be read or changed during the comparison; they are not in any group.", d.unreadable.count))
            }
            ForEach(d.groups.prefix(400)) { g in
                Section {
                    ForEach(g.files) { f in fileRow(f, g) }
                } header: {
                    HStack {
                        Text(L("%d copies · %@ each", g.files.count, ByteFormat.string(g.logicalSize))).font(.callout.weight(.semibold))
                        if g.sharesStorage {
                            Label(L("shares storage"), systemImage: "square.on.square.dashed").font(.caption)
                                .help(L("At least two of these files are APFS clones: they point to the same blocks. Removing one frees little or nothing."))
                        }
                        Spacer()
                        Text("SHA-256 " + g.digest.prefix(12) + "…").font(.caption.monospaced()).foregroundStyle(ORIX.Palette.textTertiary)
                        Menu(L("Keep…")) {
                            ForEach(g.files) { f in Button(f.path.abbreviatingHome) { model.keepOnly(f, in: g) } }
                            Divider()
                            Button(L("Keep All (clear selection)")) { model.clearGroup(g) }
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help(L("Choose the copy that stays; the others are added to the cleanup selection"))
                    }
                }
            }
            if d.groups.count > 400 { Text(L("Showing the 400 largest groups of %@.", ByteFormat.count(d.groups.count))).font(.caption).foregroundStyle(ORIX.Palette.textSecondary) }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("duplicates.list")
    }

    private func fileRow(_ f: DuplicateFile, _ g: DuplicateGroup) -> some View {
        let selected = model.isSelected(f.path)
        return HStack(spacing: ORIX.Space.s) {
            Checkbox(isOn: selected, label: L("Select %@ for cleanup", (f.path as NSString).lastPathComponent)) {
                if selected { model.basket[f.path] = nil; return }
                let remaining = g.files.filter { $0.path != f.path && !model.isSelected($0.path) }
                guard let keep = remaining.first else { model.errorMessage = L("At least one copy of each group stays. Deselect another copy first."); return }
                let before = Set(g.files.filter { model.isSelected($0.path) }.map(\.path))
                model.keepOnly(keep, in: g)
                for other in g.files where other.path != f.path && !before.contains(other.path) { model.basket[other.path] = nil }
            }
            .disabled(!f.hardLinkPaths.isEmpty)
            Thumbnail(path: f.path, side: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text((f.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                PathText(path: f.path)
            }
            Spacer()
            if !f.hardLinkPaths.isEmpty {
                Label(L("%d hard links", f.hardLinkPaths.count + 1), systemImage: "link").font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                    .help(L("This file has several names for the same data. Removing one name frees nothing, so it is not offered."))
            } else if f.mayShareBlocks {
                Label(L("may share blocks"), systemImage: "square.on.square.dashed").font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
            }
            Text(ByteFormat.date(f.modified)).font(.caption).foregroundStyle(ORIX.Palette.textSecondary).frame(width: 96, alignment: .trailing)
            if selected { Text(L("to Trash")).font(.caption.weight(.medium)).foregroundStyle(ORIX.Palette.review) }
            else { Text(L("stays")).font(.caption).foregroundStyle(ORIX.Palette.textTertiary) }
        }
        .contextMenu {
            FileMenu(path: f.path)
            Button(L("Keep Only This Copy")) { model.keepOnly(f, in: g) }
        }
        .accessibilityElement(children: .combine)
    }
}
