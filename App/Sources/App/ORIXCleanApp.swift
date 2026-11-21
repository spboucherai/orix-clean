// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : App/Sources/App/ORIXCleanApp.swift
// Description      : Application entry point, main window, menu commands and
//                    settings scene.
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
import Quartz
import SwiftUI

@main
struct ORIXCleanApp: App {
    @State private var model = AppModel(launch: .fromProcess())
    @AppStorage("appearance") private var appearance = "system"

    var scheme: ColorScheme? {
        switch model.launch.appearance ?? appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        Window("ORIX Clean", id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(scheme)
                .frame(minWidth: 980, minHeight: 620)
                .tint(ORIX.Palette.accent)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Scan Folder…")) { model.chooseFolderAndScan() }.keyboardShortcut("o")
                Button(L("Scan Home Folder")) { model.startScan(path: model.home) }.keyboardShortcut("r")
                Divider()
                Button(L("Review Cleanup Selection…")) { model.reviewBasket() }.keyboardShortcut(.return, modifiers: [.command]).disabled(model.basket.isEmpty)
                Button(L("Clear Cleanup Selection")) { model.basket.removeAll() }.keyboardShortcut(.delete, modifiers: [.command, .shift]).disabled(model.basket.isEmpty)
            }
            CommandMenu(L("Go")) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                    if i < 9 {
                        Button(s.title) { model.section = s }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    } else {
                        Button(s.title) { model.section = s }
                    }
                }
            }
        }

        Settings {
            SettingsView().environment(model).preferredColorScheme(scheme).tint(ORIX.Palette.accent)
        }
    }
}

/// Quick Look panel for a list of paths.
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var urls: [NSURL] = []

    static func show(_ paths: [String]) {
        shared.urls = paths.map { NSURL(fileURLWithPath: $0) }
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { MainActor.assumeIsolated { urls.count } }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { MainActor.assumeIsolated { urls[index] } }
}
