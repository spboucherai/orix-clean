// ORIX Clean — App/Sources/Features/Settings/SettingsView.swift
// Description: Settings: appearance, density, map palette, size accounting, permissions, privacy and stored history.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import ORIXCleanCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("density") private var density = Density.comfortable.rawValue
    @AppStorage("mapPalette") private var palette = MapPalette.orix.rawValue
    @AppStorage("sizeKind") private var sizeKind = SizeKind.allocated.rawValue
    @AppStorage("showPackageContents") private var showPackages = false
    @State private var confirmErase = false

    var body: some View {
        TabView {
            Form {
                Picker(L("Appearance"), selection: $appearance) {
                    Text(L("Match System")).tag("system"); Text(L("Light")).tag("light"); Text(L("Dark")).tag("dark")
                }
                Picker(L("List density"), selection: $density) { ForEach(Density.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker(L("Storage map colours"), selection: $palette) { ForEach(MapPalette.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker(L("Sizes in the storage map"), selection: $sizeKind) {
                    Text(L("Size on disk (allocated blocks)")).tag(SizeKind.allocated.rawValue)
                    Text(L("Content size (file length)")).tag(SizeKind.logical.rawValue)
                }
                Toggle(L("Open applications and other packages in the storage map"), isOn: $showPackages)
                Text(L("The language follows macOS (English and Canadian French). Motion follows “Reduce motion” and contrast follows “Increase contrast” in System Settings > Accessibility."))
                    .font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
            }
            .formStyle(.grouped)
            .tabItem { Label(L("General"), systemImage: "gearshape") }

            Form {
                Section(L("Access")) {
                    LabeledContent(L("Full Disk Access")) {
                        HStack {
                            Label(model.fullDiskAccess ? L("Granted") : L("Not granted"), systemImage: model.fullDiskAccess ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(model.fullDiskAccess ? ORIX.Palette.low : ORIX.Palette.textSecondary)
                            Button(L("Open Settings")) { NSWorkspace.shared.open(Permissions.fullDiskAccessSettingsURL) }
                            Button(L("Check Again")) { model.refreshEnvironment() }
                        }
                    }
                    Text(L("Optional. Without it ORIX Clean still works on everything macOS lets it read, and tells you what was not read. With it, protected folders (Mail, Safari data, the Trash, other apps' containers) are included. It never gives access to system files protected by System Integrity Protection, and ORIX Clean never asks for an administrator password."))
                        .font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                }
                Section(L("Privacy")) {
                    Text(L("ORIX Clean has no account, no network code, no analytics and no advertising. Scan results stay in memory; only volume samples, watched-folder sizes, cleanup logs and your saved actions are stored, in a local database."))
                        .font(.callout)
                    LabeledContent(L("Local database")) {
                        HStack {
                            Text(HistoryStore.defaultPath().abbreviatingHome).font(.caption.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            Button(L("Reveal")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: HistoryStore.defaultPath())]) }
                        }
                    }
                    Button(L("Erase History…"), role: .destructive) { confirmErase = true }
                        .confirmationDialog(L("Erase all recorded samples and cleanup logs?"), isPresented: $confirmErase) {
                            Button(L("Erase"), role: .destructive) {
                                model.store?.eraseAll()
                                model.operations = []; model.samples = []; model.folderSamples = [:]
                                model.refreshEnvironment()
                            }
                        } message: { Text(L("Your files are not affected. This cannot be undone.")) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label(L("Privacy & Access"), systemImage: "lock.shield") }

            Form {
                LabeledContent(L("Version"), value: model.appVersion)
                LabeledContent(L("Updates"), value: L("Manual: download new versions from the release page."))
                Text(L("ORIX Clean does not check for updates on its own because it never connects to the network."))
                    .font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
                LabeledContent(L("Safety rules")) {
                    Text(L("Removal always goes through the preview. System folders, standard folders themselves, application internals and photo-library internals are refused by the deletion engine regardless of what asks."))
                        .font(.caption).foregroundStyle(ORIX.Palette.textSecondary).frame(maxWidth: 380, alignment: .leading)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label(L("About"), systemImage: "info.circle") }
        }
        .frame(width: 640, height: 430)
    }
}
