// ORIX Clean — App/Sources/App/ORIXCleanApp.swift
// Description: Application entry point, main window, menu commands and settings scene.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
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
