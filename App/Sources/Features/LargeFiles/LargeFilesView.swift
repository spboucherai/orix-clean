// ORIX Clean — App/Sources/Features/LargeFiles/LargeFilesView.swift
// Description: Largest files and folders with filters by size, age, type and name.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import ORIXCleanCore
import SwiftUI

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("density") private var densityName = Density.comfortable.rawValue
    @State private var mode = 0
    @State private var minimumMB = 1.0
    @State private var age = 0
    @State private var category: FileCategory?
    @State private var name = ""
    @State private var includePackages = false
    @State private var lastUsed: [String: Date] = [:]

    private var density: Density { Density(rawValue: densityName) ?? .comfortable }
    static let ages: [(Int, String)] = [(0, "Any age"), (30, "Not modified for 30 days"), (180, "Not modified for 6 months"), (365, "Not modified for 1 year"), (730, "Not modified for 2 years"), (-7, "Modified in the last 7 days")]

    var body: some View {
        if let tree = model.tree {
            VStack(spacing: 0) {
                filters
                Divider()
                let hits = hits(tree)
                if hits.isEmpty {
                    EmptyState(symbol: "doc.viewfinder", title: L("Nothing matches"), message: L("No item of the scanned location passes these filters."))
                } else {
                    List {
                        Section(L("%@ items · %@ on disk", ByteFormat.count(hits.count), ByteFormat.string(hits.reduce(0) { $0 + tree[$1.node].allocatedSize }))) {
                            ForEach(hits) { h in row(h.node, tree) }
                        }
                    }
                    .listStyle(.inset)
                    .accessibilityIdentifier("large.list")
                }
                if age > 0 {
                    InfoBanner(text: L("“Not modified” is the modification date stored by the filesystem. It does not prove a file is unused: something you only read keeps its old date. The “last opened” date shown for some files comes from Spotlight, when it recorded one."))
                        .padding(ORIX.Space.s)
                }
            }
        } else {
            EmptyState(symbol: "doc.viewfinder", title: L("No scan yet"), message: L("Scan a folder or a volume to list its largest files and folders."),
                       actionTitle: L("Scan Home Folder")) { model.startScan(path: model.home) }
        }
    }

    private var filters: some View {
        HStack(spacing: ORIX.Space.m) {
            Picker(L("Show"), selection: $mode) {
                Text(L("Files")).tag(0)
                Text(L("Folders")).tag(1)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            HStack(spacing: 4) {
                Text(L("At least")).font(.callout)
                Slider(value: $minimumMB, in: 0 ... 3, step: 0.01) { Text(L("Minimum size")) }.labelsHidden().frame(width: 120)
                    .accessibilityValue(ByteFormat.string(minimumBytes))
                Text(ByteFormat.string(minimumBytes)).font(.callout.monospacedDigit()).frame(width: 70, alignment: .leading)
            }
            Picker(L("Age"), selection: $age) { ForEach(Self.ages, id: \.0) { Text(L($0.1)).tag($0.0) } }.labelsHidden().frame(width: 210).disabled(mode == 1)
            Picker(L("Type"), selection: $category) {
                Text(L("All types")).tag(FileCategory?.none)
                ForEach(FileCategory.allCases, id: \.self) { Text($0.title).tag(FileCategory?.some($0)) }
            }.labelsHidden().frame(width: 140).disabled(mode == 1)
            TextField(L("Name contains"), text: $name).textFieldStyle(.roundedBorder).frame(minWidth: 100, maxWidth: 180).disabled(mode == 1)
            Toggle(L("Inside packages"), isOn: $includePackages).toggleStyle(.checkbox).disabled(mode == 1)
                .help(L("Also list files inside applications, photo libraries and other packages"))
            Spacer()
        }
        .padding(.horizontal, ORIX.Space.m).padding(.vertical, ORIX.Space.s)
        .background(.bar)
    }

    /// Slider position 0…3 maps to 1 MB … 1 GB on a log scale (0 = no minimum).
    private var minimumBytes: Int64 { minimumMB <= 0 ? 0 : Int64(pow(10, minimumMB) * 1_000_000 / 1) }

    private func hits(_ tree: ScanTree) -> [FileHit] {
        _ = model.treeVersion
        if mode == 1 { return TreeQuery.largestFolders(in: tree, minimumSize: minimumBytes, limit: 300) }
        var f = FileFilter()
        f.minimumSize = minimumBytes
        if age > 0 { f.modifiedBefore = Date().addingTimeInterval(-Double(age) * 86400) }
        if age < 0 { f.modifiedAfter = Date().addingTimeInterval(Double(age) * 86400) }
        if let category { f.categories = [category] }
        f.nameContains = name
        f.includePackageContents = includePackages
        return TreeQuery.largestFiles(in: tree, filter: f, limit: 500)
    }

    private func row(_ i: Int32, _ tree: ScanTree) -> some View {
        let n = tree[i]
        let path = tree.path(of: i)
        return HStack(spacing: ORIX.Space.s) {
            Checkbox(isOn: model.isSelected(path), label: L("Select %@ for cleanup", tree.name(of: i))) {
                if let item = model.item(forNode: i) { model.toggle(item) }
            }
            FileIcon(path: path, size: density == .compact ? 18 : 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(tree.name(of: i)).lineLimit(1).truncationMode(.middle)
                if density == .comfortable { PathText(path: path) }
            }
            Spacer(minLength: ORIX.Space.s)
            if n.flags.contains(.mayShareBlocks) {
                Image(systemName: "square.on.square.dashed").foregroundStyle(ORIX.Palette.textSecondary)
                    .help(L("APFS reports that this file may share blocks with another file. Removing it may free less than its size."))
                    .accessibilityLabel(L("may share blocks"))
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(L("Modified %@", ByteFormat.date(Date(timeIntervalSince1970: TimeInterval(n.modified))))).font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                if let d = lastUsed[path] { Text(L("Last opened %@", ByteFormat.date(d))).font(.caption2).foregroundStyle(ORIX.Palette.textTertiary) }
            }
            .frame(width: 170, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) {
                SizeText(bytes: n.allocatedSize)
                if abs(n.logicalSize - n.allocatedSize) > max(1_000_000, n.allocatedSize / 10) {
                    Text(L("%@ content", ByteFormat.string(n.logicalSize))).font(.caption2.monospacedDigit()).foregroundStyle(ORIX.Palette.textTertiary)
                }
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, density.rowPadding - 3)
        .contextMenu {
            FileMenu(path: path)
            Button(L("Show in Storage Map")) { model.mapFocus = n.flags.contains(.directory) ? i : n.parent; model.mapSelection = i; model.section = .map }
        }
        .task(id: path) {
            if lastUsed[path] == nil, !n.flags.contains(.directory) {
                if let d = await model.background({ AppInventory.lastUsed(path) }) { lastUsed[path] = d }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
