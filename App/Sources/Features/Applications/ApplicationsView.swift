// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : App/Sources/Features/Applications/ApplicationsView.swift
// Description      : Uninstall assistant (application + associated files with
//                    stated certainty) and leftover detection.
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

import ORIXCleanCore
import SwiftUI

struct ApplicationsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    @State private var search = ""
    @State private var sortBySize = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text(L("Installed Applications")).tag(0)
                    Text(L("Leftover Files")).tag(1)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
                Spacer()
                if tab == 0 {
                    Toggle(L("Largest first"), isOn: $sortBySize).toggleStyle(.checkbox)
                    TextField(L("Search applications"), text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                }
            }
            .padding(.horizontal, ORIX.Space.m).padding(.vertical, ORIX.Space.s).background(.bar)
            Divider()
            if tab == 0 { installed } else { leftovers }
        }
        .onAppear { model.loadApps() }
    }

    private var installed: some View {
        @Bindable var model = model
        let apps = model.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
            .sorted { sortBySize ? ($0.measurement?.allocated ?? 0) > ($1.measurement?.allocated ?? 0) : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return HSplitView {
            List(apps, selection: $model.selectedApp) { app in
                HStack(spacing: ORIX.Space.s) {
                    FileIcon(path: app.path, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).lineLimit(1)
                        Text(app.isSystem ? L("Part of macOS") : app.version).font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                    }
                    Spacer()
                    if let m = app.measurement { Text(ByteFormat.string(m.allocated)).font(.callout.monospacedDigit()) } else { ProgressView().controlSize(.mini) }
                }
                .tag(app.path)
                .accessibilityElement(children: .combine)
            }
            .listStyle(.inset)
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)
            .accessibilityIdentifier("apps.list")
            Group {
                if let app = model.apps.first(where: { $0.path == model.selectedApp }) {
                    AppDetail(app: app)
                } else {
                    EmptyState(symbol: "square.grid.2x2", title: L("Choose an application"),
                               message: L("ORIX Clean shows its size, who signed it, and the files in your Library that carry its identifier. Your documents are never part of an uninstall."))
                }
            }
            .frame(minWidth: 420)
        }
    }

    private var leftovers: some View {
        VStack(spacing: 0) {
            CandidateHeader(title: L("Leftover Files"),
                            subtitle: L("Library items named after an application identifier for which no installed application was found. This is an inference from names: command-line tools, plug-ins and apps on other volumes can look like leftovers. Review each one."),
                            items: model.leftovers.map(\.cleanupItem), phase: model.leftoversPhase) { model.loadLeftovers() }
            Divider()
            if model.leftoversPhase == .idle {
                EmptyState(symbol: "questionmark.folder", title: L("Look for leftover files"), message: L("Compares identifiers found in your Library with the installed applications."),
                           actionTitle: L("Search")) { model.loadLeftovers() }
            } else if model.leftovers.isEmpty, model.leftoversPhase == .done {
                EmptyState(symbol: "checkmark.seal", title: L("No likely leftovers"), message: L("Every identifier found in your Library matches an installed application or its vendor."))
            } else {
                List { ForEach(model.leftovers) { CandidateRow(item: $0.cleanupItem) } }.listStyle(.inset).accessibilityIdentifier("leftovers.list")
            }
        }
    }
}

struct AppDetail: View {
    @Environment(AppModel.self) private var model
    var app: InstalledApp

    var body: some View {
        let files = model.associated[app.path]
        ScrollView {
            VStack(alignment: .leading, spacing: ORIX.Space.l) {
                HStack(spacing: ORIX.Space.m) {
                    FileIcon(path: app.path, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title2.weight(.semibold))
                        Text(app.bundleID).font(.callout.monospaced()).foregroundStyle(ORIX.Palette.textSecondary).textSelection(.enabled)
                        PathText(path: app.path + "/x")
                    }
                    Spacer()
                    if model.runningBundleIDs.contains(app.bundleID) { Label(L("running"), systemImage: "play.circle").foregroundStyle(ORIX.Palette.review) }
                }
                Card {
                    Grid(alignment: .leading, horizontalSpacing: ORIX.Space.l, verticalSpacing: 6) {
                        fact(L("Version"), "\(app.version) (\(app.build))")
                        fact(L("Size on disk"), app.measurement.map { ByteFormat.string($0.allocated) } ?? "…")
                        fact(L("Signed by"), signatureText)
                        fact(L("Developer team"), app.signature?.teamID ?? "—")
                        fact(L("Last used"), app.lastUsed.map(ByteFormat.date) ?? L("Not recorded by Spotlight"))
                    }
                }
                if app.isSystem {
                    InfoBanner(symbol: "lock.shield", text: L("This application is part of macOS. ORIX Clean does not remove system applications."))
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: ORIX.Space.s) {
                            SectionTitle(title: L("Associated files"), subtitle: L("Found in your Library. The certainty of each match is stated; name-only matches are high risk and never preselected."))
                            if let files {
                                if files.isEmpty { Text(L("No associated file found.")).font(.callout).foregroundStyle(ORIX.Palette.textSecondary) }
                                ForEach(AppInventory.uninstallItems(app: app, files: files).dropFirst()) { CandidateRow(item: $0) }
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    HStack {
                        Spacer()
                        Button(L("Select Application Only")) { selectForUninstall(files: []) }
                        Button(L("Select Application and Identifier-Matched Files")) { selectForUninstall(files: (files ?? []).filter { $0.confidence == .identifier }) }
                            .buttonStyle(.borderedProminent).disabled(files == nil)
                            .accessibilityIdentifier("apps.selectUninstall")
                    }
                    Text(L("Selecting adds the items to the cleanup selection. Nothing is removed until you review and confirm."))
                        .font(.caption).foregroundStyle(ORIX.Palette.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(ORIX.Space.l)
        }
        .onAppear { model.loadAssociated(for: app) }
        .onChange(of: app.path) { model.loadAssociated(for: app) }
    }

    private var signatureText: String {
        guard let s = app.signature else { return "…" }
        let validity = s.valid ? "" : " — " + L("signature does not validate")
        switch s.kind {
        case .apple: return L("Apple (system software)") + validity
        case .appStore: return L("Mac App Store") + validity
        case .developerID: return (s.authority ?? "Developer ID") + validity
        case .adHoc: return L("Ad-hoc signature (no identity)")
        case .unsigned: return L("Not signed")
        case .other: return (s.authority ?? L("Other certificate")) + validity
        }
    }

    private func fact(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).font(.callout).foregroundStyle(ORIX.Palette.textSecondary)
            Text(v).font(.callout).textSelection(.enabled)
        }
    }

    private func selectForUninstall(files: [AssociatedFile]) {
        model.select(AppInventory.uninstallItems(app: app, files: files))
    }
}
