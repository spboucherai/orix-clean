// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : App/Sources/Features/StorageMap/StorageMapView.swift
// Description      : Interactive treemap of the scanned tree: drill down, zoom,
//                    pan, hover details, search, selection for cleanup.
// Module           : Features
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

struct StorageMapView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("mapPalette") private var paletteName = MapPalette.orix.rawValue
    @AppStorage("sizeKind") private var sizeKindName = SizeKind.allocated.rawValue
    @AppStorage("showPackageContents") private var showPackages = false
    @State private var hover: TreemapCell?
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero
    @State private var search = ""
    @State private var showList = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: MapPalette { MapPalette(rawValue: paletteName) ?? .orix }
    private var sizeKind: SizeKind { SizeKind(rawValue: sizeKindName) ?? .allocated }

    var body: some View {
        if let tree = model.tree {
            VStack(spacing: 0) {
                header(tree)
                Divider()
                HSplitView {
                    map(tree).frame(minWidth: 420)
                    if showList { sideList(tree).frame(minWidth: 260, idealWidth: 320, maxWidth: 460) }
                }
                Divider()
                footer(tree)
            }
            .onChange(of: model.mapFocus) { resetView() }
        } else {
            EmptyState(symbol: "square.grid.3x3.square", title: L("No scan yet"),
                       message: L("Scan a folder or a volume to see where the space goes. Every block of the map is a real file or folder, sized by its measured size."),
                       actionTitle: L("Scan Home Folder")) { model.startScan(path: model.home) }
        }
    }

    private func resetView() { zoom = 1; zoomBase = 1; offset = .zero; dragBase = .zero; hover = nil }

    // MARK: Header (breadcrumb, search, controls)

    private func header(_ tree: ScanTree) -> some View {
        HStack(spacing: ORIX.Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tree.ancestors(of: model.mapFocus) + [model.mapFocus], id: \.self) { i in
                        if i != 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(ORIX.Palette.textTertiary).accessibilityHidden(true) }
                        Button(tree.displayName(of: i)) { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { model.mapFocus = i } }
                            .buttonStyle(.plain).font(.callout.weight(i == model.mapFocus ? .semibold : .regular))
                            .foregroundStyle(i == model.mapFocus ? Color.primary : ORIX.Palette.textSecondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                    }
                }
            }
            .accessibilityLabel(L("Location"))
            .frame(minWidth: 80)
            Spacer(minLength: 4)
            TextField(L("Search names"), text: $search).textFieldStyle(.roundedBorder).frame(minWidth: 110, idealWidth: 190, maxWidth: 190)
                .accessibilityIdentifier("map.search")
            Picker(L("Size"), selection: $sizeKindName) {
                Text(L("On disk")).tag(SizeKind.allocated.rawValue)
                Text(L("Content")).tag(SizeKind.logical.rawValue)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help(L("On disk: blocks allocated. Content: length of the files."))
            Button { if model.mapFocus != 0, let t = model.tree { model.mapFocus = t[model.mapFocus].parent } } label: { Image(systemName: "arrow.up") }
                .disabled(model.mapFocus == 0).help(L("Enclosing folder")).keyboardShortcut(.upArrow, modifiers: .command)
                .accessibilityLabel(L("Enclosing folder"))
            Button { resetView() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .disabled(zoom == 1 && offset == .zero).help(L("Reset zoom")).accessibilityLabel(L("Reset zoom"))
            Toggle(isOn: $showList) { Image(systemName: "sidebar.right") }.toggleStyle(.button).help(L("Show the list")).accessibilityLabel(L("Show the list"))
        }
        .padding(.horizontal, ORIX.Space.m).padding(.vertical, ORIX.Space.s)
        .background(.bar)
    }

    // MARK: Map

    private func cells(_ tree: ScanTree, size: CGSize) -> [TreemapCell] {
        var o = TreemapOptions()
        o.sizeKind = sizeKind
        o.showPackageContents = showPackages
        o.visible = CGRect(origin: .zero, size: size)
        let virtual = CGRect(x: offset.width, y: offset.height, width: size.width * zoom, height: size.height * zoom)
        return Treemap.layout(tree: tree, root: model.mapFocus, in: virtual, options: o)
    }

    private func map(_ tree: ScanTree) -> some View {
        GeometryReader { geo in
            let _ = model.treeVersion
            let size = geo.size
            let cells = cells(tree, size: size)
            let needle = search.lowercased()
            Canvas(opaque: true, rendersAsynchronously: false) { ctx, _ in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ORIX.Palette.canvas))
                for cell in cells { draw(cell, tree: tree, in: &ctx, needle: needle) }
                if let h = hover {
                    ctx.stroke(Path(roundedRect: h.rect.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(.white), lineWidth: 2)
                    ctx.stroke(Path(roundedRect: h.rect.insetBy(dx: 2.5, dy: 2.5), cornerRadius: 2), with: .color(.black.opacity(0.55)), lineWidth: 1)
                }
                if let sel = model.mapSelection, let c = cells.first(where: { $0.node == sel && $0.aggregateCount == 0 }) {
                    ctx.stroke(Path(roundedRect: c.rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 3), with: .color(ORIX.Palette.accent), style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(p): hover = hit(p, cells)
                case .ended: hover = nil
                }
            }
            .gesture(SpatialTapGesture(count: 2).onEnded { v in
                if let c = hit(v.location, cells), c.aggregateCount == 0 { open(c.node, tree) }
            })
            .simultaneousGesture(SpatialTapGesture().onEnded { v in
                if let c = hit(v.location, cells), c.aggregateCount == 0 { model.mapSelection = c.node } else { model.mapSelection = nil }
            })
            .gesture(MagnifyGesture().onChanged { v in
                let newZoom = min(12, max(1, zoomBase * v.magnification))
                let anchor = v.startLocation
                // Keep the point under the fingers fixed.
                let fx = (anchor.x - offset.width) / (size.width * zoom), fy = (anchor.y - offset.height) / (size.height * zoom)
                zoom = newZoom
                offset = clamp(CGSize(width: anchor.x - fx * size.width * zoom, height: anchor.y - fy * size.height * zoom), size)
            }.onEnded { _ in zoomBase = zoom; dragBase = offset })
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { v in
                guard zoom > 1 else { return }
                offset = clamp(CGSize(width: dragBase.width + v.translation.width, height: dragBase.height + v.translation.height), size)
            }.onEnded { _ in dragBase = offset })
            .contextMenu {
                if let sel = model.mapSelection ?? hover?.node, sel != 0 {
                    let path = tree.path(of: sel)
                    if tree[sel].flags.contains(.directory) { Button(L("Open in Map")) { open(sel, tree) } }
                    FileMenu(path: path)
                    Divider()
                    Button(model.isSelected(path) ? L("Remove from Cleanup Selection") : L("Add to Cleanup Selection")) {
                        if let item = model.item(forNode: sel) { model.toggle(item) }
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L("Storage map of %@", tree.displayName(of: model.mapFocus)))
            .accessibilityValue(L("%d regions. Use the list next to the map to browse with VoiceOver.", cells.count))
            .accessibilityIdentifier("map.canvas")
        }
    }

    private func clamp(_ o: CGSize, _ size: CGSize) -> CGSize {
        CGSize(width: min(0, max(size.width - size.width * zoom, o.width)), height: min(0, max(size.height - size.height * zoom, o.height)))
    }

    private func open(_ node: Int32, _ tree: ScanTree) {
        var target = node
        if !tree[target].flags.contains(.directory) || tree[target].childCount == 0 { target = tree[target].parent }
        if target >= 0 { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { model.mapFocus = target } }
    }

    /// Deepest cell under the point. Cells are in parent-before-child order.
    private func hit(_ p: CGPoint, _ cells: [TreemapCell]) -> TreemapCell? {
        var best: TreemapCell?
        for c in cells where c.rect.contains(p) { if best == nil || c.depth >= best!.depth { best = c } }
        return best
    }

    private func draw(_ cell: TreemapCell, tree: ScanTree, in ctx: inout GraphicsContext, needle: String) {
        let r = cell.rect
        guard r.width > 0.5, r.height > 0.5 else { return }
        let node = tree[cell.node]
        if !cell.isLeaf {
            // Folder frame with its name in the header strip.
            ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(ORIX.Palette.surfaceRaised.opacity(cell.depth % 2 == 0 ? 0.92 : 0.7)))
            ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: .color(ORIX.Palette.hairline), lineWidth: 1)
            if r.height > 33, r.width > 46 {
                let text = Text(tree.name(of: cell.node)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.8))
                let size = Text(ByteFormat.string(tree.size(of: cell.node, sizeKind))).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
                var clipped = ctx
                clipped.clip(to: Path(CGRect(x: r.minX + 4, y: r.minY, width: r.width - 8, height: 16)))
                let resolved = clipped.resolve(text)
                let w = resolved.measure(in: CGSize(width: 2000, height: 16)).width
                clipped.draw(resolved, at: CGPoint(x: r.minX + 5, y: r.minY + 8.5), anchor: .leading)
                if r.width > w + 80 { clipped.draw(size, at: CGPoint(x: r.maxX - 5, y: r.minY + 8.5), anchor: .trailing) }
            }
            return
        }
        var category: FileCategory = .other
        var isFolder = false
        if cell.aggregateCount > 0 {
            category = .other
        } else if node.flags.contains(.directory) {
            isFolder = true
            let ext = tree.fileExtension(of: cell.node)
            category = node.flags.contains(.package) ? (ext == "app" ? .application : FileCategory.of(extension: ext)) : .other
        } else {
            category = FileCategory.of(extension: tree.fileExtension(of: cell.node))
        }
        let base = palette.color(category)
        let shade = 1.0 - Double(min(cell.depth, 7)) * 0.035
        var color = Color(.sRGB, red: base.r * shade, green: base.g * shade, blue: base.b * shade, opacity: 1)
        if cell.aggregateCount > 0 { color = ORIX.Palette.textTertiary.opacity(0.45) }
        else if isFolder, !node.flags.contains(.package) { color = ORIX.Palette.accentSecondary.opacity(0.55) }
        let matches = !needle.isEmpty && cell.aggregateCount == 0 && tree.name(of: cell.node).lowercased().contains(needle)
        if !needle.isEmpty, !matches { color = color.opacity(0.22) }
        let inner = r.insetBy(dx: r.width > 4 ? 0.75 : 0, dy: r.height > 4 ? 0.75 : 0)
        let path = Path(roundedRect: inner, cornerRadius: min(3, inner.width / 4, inner.height / 4))
        ctx.fill(path, with: .color(color))
        if inner.width > 14, inner.height > 14 {
            // Soft top-left light for depth.
            ctx.fill(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.10)]),
                                                 startPoint: CGPoint(x: inner.minX, y: inner.minY), endPoint: CGPoint(x: inner.maxX, y: inner.maxY)))
        }
        if model.isSelected(cell.aggregateCount == 0 ? tree.path(of: cell.node) : "") {
            ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
        if inner.width > 54, inner.height > 26 {
            let name = cell.aggregateCount > 0 ? L("%d smaller items", cell.aggregateCount) : tree.name(of: cell.node)
            let bytes = cell.aggregateCount > 0 ? cell.aggregateSize : tree.size(of: cell.node, sizeKind)
            var clipped = ctx
            clipped.clip(to: Path(inner.insetBy(dx: 4, dy: 2)))
            let dark = palette == .colorblind && category == .application
            let fg: Color = dark ? .black.opacity(0.85) : .white
            clipped.draw(Text(name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(fg), at: CGPoint(x: inner.minX + 5, y: inner.minY + 9), anchor: .leading)
            if inner.height > 38 {
                clipped.draw(Text(ByteFormat.string(bytes)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(fg.opacity(0.85)),
                             at: CGPoint(x: inner.minX + 5, y: inner.minY + 22), anchor: .leading)
            }
        }
    }

    // MARK: Side list (accessible equivalent of the map)

    private func sideList(_ tree: ScanTree) -> some View {
        let _ = model.treeVersion
        let needle = search.lowercased()
        let children: [Int32]
        if needle.isEmpty {
            children = tree.sortedChildren(of: model.mapFocus, by: sizeKind)
        } else {
            var f = FileFilter(); f.nameContains = needle; f.under = model.mapFocus; f.sizeKind = sizeKind; f.includePackageContents = showPackages
            children = TreeQuery.largestFiles(in: tree, filter: f, limit: 300).map(\.node)
        }
        let total = max(1, tree.size(of: model.mapFocus, sizeKind))
        return List(selection: Binding(get: { model.mapSelection }, set: { model.mapSelection = $0 })) {
            Section(needle.isEmpty ? L("%@ items in %@", ByteFormat.count(children.count), tree.displayName(of: model.mapFocus)) : L("%@ matches", ByteFormat.count(children.count))) {
                ForEach(children.prefix(600), id: \.self) { c in
                    let n = tree[c]
                    HStack(spacing: 8) {
                        Checkbox(isOn: model.isSelected(tree.path(of: c)), label: L("Select %@ for cleanup", tree.name(of: c))) {
                            if let item = model.item(forNode: c) { model.toggle(item) }
                        }
                        Image(systemName: n.flags.contains(.directory) ? (n.flags.contains(.package) ? "shippingbox" : "folder.fill") : "doc")
                            .foregroundStyle(n.flags.contains(.directory) ? ORIX.Palette.accentSecondary : ORIX.Palette.textSecondary).frame(width: 16).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tree.name(of: c)).lineLimit(1).truncationMode(.middle)
                            ProportionBar(fraction: Double(tree.size(of: c, sizeKind)) / Double(total), height: 3)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(ByteFormat.string(tree.size(of: c, sizeKind))).font(.callout.monospacedDigit())
                            if n.flags.contains(.unreadable) { Text(L("not readable")).font(.caption2).foregroundStyle(ORIX.Palette.review) }
                            else if n.flags.contains(.boundary) { Text(L("other volume")).font(.caption2).foregroundStyle(ORIX.Palette.textSecondary) }
                            else if n.flags.contains(.dataless) { Text(L("in iCloud")).font(.caption2).foregroundStyle(ORIX.Palette.textSecondary) }
                        }
                    }
                    .tag(c)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { open(c, tree) }
                    .contextMenu {
                        if n.flags.contains(.directory) { Button(L("Open in Map")) { open(c, tree) } }
                        FileMenu(path: tree.path(of: c))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: L("Open in Map")) { open(c, tree) }
                }
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("map.list")
    }

    // MARK: Footer (details of the hovered or selected region)

    private func footer(_ tree: ScanTree) -> some View {
        let cell = hover
        let node = cell?.aggregateCount == 0 ? cell?.node : nil
        let shown = node ?? model.mapSelection
        return HStack(spacing: ORIX.Space.m) {
            if let cell, cell.aggregateCount > 0 {
                Text(L("%d smaller items in %@ · %@", cell.aggregateCount, tree.displayName(of: cell.node), ByteFormat.string(cell.aggregateSize))).font(.callout)
            } else if let i = shown {
                let n = tree[i]
                FileIcon(path: tree.path(of: i), size: 18)
                Text(tree.path(of: i).abbreviatingHome).font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer()
                if n.flags.contains(.mayShareBlocks) { Label(L("may share blocks"), systemImage: "square.on.square.dashed").font(.caption).foregroundStyle(ORIX.Palette.textSecondary) }
                if n.flags.contains(.hardLinked) { Label(L("hard-linked"), systemImage: "link").font(.caption).foregroundStyle(ORIX.Palette.textSecondary) }
                if n.flags.contains(.sparse) { Label(L("sparse"), systemImage: "circle.dotted").font(.caption).foregroundStyle(ORIX.Palette.textSecondary) }
                if n.flags.contains(.directory) { Text(L("%@ files", ByteFormat.count(Int(n.fileCount)))).font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary) }
                Text(L("%@ on disk · %@ content", ByteFormat.string(n.allocatedSize), ByteFormat.string(n.logicalSize))).font(.callout.monospacedDigit())
            } else {
                Text(L("Double-click a folder to open it. Pinch to zoom, drag to pan. Right-click for actions.")).font(.callout).foregroundStyle(ORIX.Palette.textSecondary).lineLimit(1)
                Spacer()
                ForEach(FileCategory.allCases, id: \.self) { c in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(palette.swiftUIColor(c)).frame(width: 9, height: 9)
                        Text(c.title).font(.caption2).foregroundStyle(ORIX.Palette.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, ORIX.Space.m).frame(height: 30)
        .background(.bar)
        .accessibilityIdentifier("map.footer")
    }
}
