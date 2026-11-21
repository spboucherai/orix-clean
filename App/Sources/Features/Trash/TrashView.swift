// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : App/Sources/Features/Trash/TrashView.swift
// Description      : Trash inventory per volume and permanent deletion with
//                    explicit confirmation.
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

struct TrashView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = model.trash.flatMap(\.items)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: ORIX.Space.m) {
                SectionTitle(title: L("Trash"), subtitle: L("Items in the Trash still occupy disk space. Emptying is permanent: afterwards they can only come back from a backup."))
                Spacer()
                if model.trashPhase == .running { ProgressView().controlSize(.small) }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormat.string(model.trash.reduce(0) { $0 + $1.allocated })).font(.title3.weight(.semibold).monospacedDigit())
                    Text(L("%@ items", ByteFormat.count(all.count))).font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                }
                Button { model.loadTrash(force: true) } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel(L("Measure again"))
                Button(L("Empty Trash…")) { model.reviewEmptyTrash(all) }.disabled(all.isEmpty).accessibilityIdentifier("trash.empty")
            }
            .padding(ORIX.Space.l)
            Divider()
            if model.trash.contains(where: { !$0.accessible }) {
                InfoBanner(symbol: "lock", text: L("macOS did not allow reading the Trash. Grant Full Disk Access to ORIX Clean to see its content, or empty it from Finder."),
                           actionTitle: L("Open Settings")) { NSWorkspace.shared.open(Permissions.fullDiskAccessSettingsURL) }.padding(ORIX.Space.m)
            }
            if all.isEmpty, model.trashPhase == .done {
                EmptyState(symbol: "trash", title: model.trash.contains { !$0.accessible } ? L("Trash content unknown") : L("The Trash is empty"),
                           message: L("Items you clean with ORIX Clean arrive here first, so you can put them back."))
            } else {
                List {
                    ForEach(model.trash.filter { !$0.items.isEmpty }) { loc in
                        Section("\(loc.volumeName) · \(ByteFormat.string(loc.allocated)) · " + L("%@ files", ByteFormat.count(loc.fileCount))) {
                            ForEach(loc.items) { item in
                                HStack(spacing: ORIX.Space.s) {
                                    FileIcon(path: item.path, size: 22)
                                    Text(item.name).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    if let d = item.measurement.modified { Text(ByteFormat.date(d)).font(.caption).foregroundStyle(ORIX.Palette.textSecondary) }
                                    SizeText(bytes: item.measurement.allocated).frame(width: 100, alignment: .trailing)
                                }
                                .contextMenu {
                                    FileMenu(path: item.path)
                                    Button(L("Delete Permanently…")) { model.reviewEmptyTrash([item]) }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("trash.list")
            }
        }
        .onAppear { model.loadTrash(force: true) }
    }
}
