// ORIX Clean — App/Sources/App/RootView.swift
// Description: Main window: sidebar, section content, scan status, cleanup selection bar, preview and result sheets.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import ORIXCleanCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("onboarded") private var onboarded = false
    @State private var showOnboarding = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) {
                ForEach(AppSection.groups, id: \.0) { group in
                    Section(group.0.isEmpty ? "" : L(group.0)) {
                        ForEach(group.1) { s in
                            Label(s.title, systemImage: s.symbol)
                                .tag(s)
                                .badge(badge(for: s))
                                .accessibilityIdentifier("sidebar." + s.rawValue)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 212, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            VStack(spacing: 0) {
                ScanStatusBar()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ORIX.Palette.canvas)
                SelectionBar()
            }
            .navigationTitle(model.section.title)
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItemGroup {
                    Button { model.chooseFolderAndScan() } label: { Label(L("Scan Folder…"), systemImage: "folder.badge.gearshape") }
                        .help(L("Choose a folder or a volume to analyze"))
                        .accessibilityIdentifier("toolbar.scanFolder")
                    Button { model.startScan(path: model.scan?.tree.rootPath ?? model.home) } label: { Label(L("Rescan"), systemImage: "arrow.clockwise") }
                        .help(L("Scan the same location again"))
                        .disabled(model.scanPhase == .running)
                }
            }
        }
        .sheet(item: $model.preview) { request in
            CleanupPreviewSheet(request: request).environment(model)
        }
        .sheet(isPresented: $model.showResults) {
            if let report = model.lastReport { CleanupResultsSheet(reportID: report.id).environment(model) }
        }
        .sheet(isPresented: $showOnboarding) { OnboardingSheet { onboarded = true; showOnboarding = false }.environment(model) }
        .alert(L("ORIX Clean"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L("OK")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .overlay { if model.cleaning { CleaningOverlay() } }
        .onAppear {
            if !onboarded, !model.launch.skipOnboarding { showOnboarding = true }
            if let root = model.launch.scanRoot { model.startScan(path: root) }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "ORIXOpenSettings") { openSettings() }
            if let demo = UserDefaults.standard.string(forKey: "ORIXDemoSelect") {
                Task { await model.runDemo(demo, confirm: UserDefaults.standard.bool(forKey: "ORIXDemoConfirm")) }
            }
            #endif
            if let size = model.launch.windowSize {
                DispatchQueue.main.async {
                    guard let w = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
                    var f = w.frame
                    f.origin.y += f.height - size.height
                    f.size = size
                    w.setFrame(f, display: true)
                }
            }
        }
    }

    private var subtitle: String {
        guard let scan = model.scan else { return L("No scan yet") }
        _ = model.treeVersion
        return L("%@ · %@ on disk", scan.tree.rootPath.abbreviatingHome, ByteFormat.string(scan.tree[0].allocatedSize))
    }

    private func badge(for s: AppSection) -> Text? {
        switch s {
        case .duplicates: return model.duplicates.map { Text(ByteFormat.count($0.groups.count)) }
        case .similar: return model.similar.map { Text(ByteFormat.count($0.groups.count)) }
        default: return nil
        }
    }

    @ViewBuilder private var content: some View {
        switch model.section {
        case .overview: OverviewView()
        case .map: StorageMapView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .similar: SimilarImagesView()
        case .caches: CachesView()
        case .developer: DeveloperView()
        case .downloads: DownloadsView()
        case .applications: ApplicationsView()
        case .trash: TrashView()
        case .history: HistoryView()
        case .actions: ActionsView()
        case .reports: ReportsView()
        }
    }
}

struct SidebarFooter: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let v = model.startupVolume {
            VStack(alignment: .leading, spacing: 4) {
                Text(v.name).font(.caption.weight(.semibold)).lineLimit(1)
                ProportionBar(fraction: 1 - v.freeFraction, color: v.freeFraction < 0.1 ? ORIX.Palette.review : ORIX.Palette.accent, height: 5)
                Text(L("%@ free of %@", ByteFormat.string(v.available), ByteFormat.string(v.total)))
                    .font(.caption2.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
            }
            .padding(ORIX.Space.m)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("%@: %@ free of %@", v.name, ByteFormat.string(v.available), ByteFormat.string(v.total)))
        }
    }
}

/// Live scan progress with real counters. Shown only while a scan runs or failed.
struct ScanStatusBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.scanPhase {
        case .running:
            HStack(spacing: ORIX.Space.m) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.scanPaused ? L("Scan paused") : L("Scanning…")).font(.callout.weight(.medium))
                    Text(L("%@ files · %@ folders · %@ · %@", ByteFormat.count(model.scanProgress.files), ByteFormat.count(model.scanProgress.directories),
                           ByteFormat.string(model.scanProgress.allocatedBytes), model.scanProgress.currentPath.abbreviatingHome))
                        .font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(model.scanPaused ? L("Resume") : L("Pause")) { model.toggleScanPause() }
                Button(L("Cancel")) { model.cancelScan() }.accessibilityIdentifier("scan.cancel")
            }
            .padding(.horizontal, ORIX.Space.l).padding(.vertical, ORIX.Space.s)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        case let .failed(message):
            InfoBanner(symbol: "exclamationmark.circle", text: message, actionTitle: L("Dismiss")) { model.scanPhase = model.scan == nil ? .idle : .done }
                .padding(ORIX.Space.s)
        default:
            EmptyView()
        }
    }
}

/// Persistent summary of what is ticked for cleanup. Nothing is removed from here; it opens the preview.
struct SelectionBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if !model.basket.isEmpty {
            let plan = model.basketPlan
            HStack(spacing: ORIX.Space.m) {
                Image(systemName: "checklist").foregroundStyle(ORIX.Palette.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("%@ items selected for cleanup", ByteFormat.count(plan.items.count))).font(.callout.weight(.medium))
                    Text(L("%@ on disk · estimated recoverable %@", ByteFormat.string(plan.allocatedSize), plan.recoverable.text))
                        .font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
                }
                Spacer()
                Button(L("Clear")) { model.basket.removeAll() }
                Button(L("Review…")) { model.reviewBasket() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityIdentifier("selection.review")
            }
            .padding(.horizontal, ORIX.Space.l).padding(.vertical, ORIX.Space.s)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

struct CleaningOverlay: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: ORIX.Space.m) {
                Text(L("Cleaning…")).font(.headline)
                ProgressView(value: Double(model.cleanupDone), total: Double(max(1, model.cleanupTotal))).frame(width: 280)
                Text(L("%d of %d items", model.cleanupDone, model.cleanupTotal)).font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
                Button(L("Stop")) { model.cancelCleanup() }.help(L("Items already moved stay in the Trash; the rest is left untouched"))
            }
            .padding(ORIX.Space.xl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ORIX.Radius.l))
        }
    }
}

struct OnboardingSheet: View {
    @Environment(AppModel.self) private var model
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: ORIX.Space.l) {
            HStack(spacing: ORIX.Space.m) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ORIX Clean").font(.largeTitle.weight(.bold))
                    Text(L("Reclaim space. Keep control.")).font(.title3).foregroundStyle(ORIX.Palette.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: ORIX.Space.m) {
                point("ruler", L("Every size is measured"), L("Sizes come from the filesystem during the scan. Nothing is estimated from file names and nothing is simulated."))
                point("hand.raised", L("Nothing is removed without you"), L("Every cleanup shows the exact list of items first. You confirm, and items go to the Trash so you can put them back."))
                point("lock.shield", L("Everything stays on this Mac"), L("No account, no network connection, no analytics. ORIX Clean has no code that sends data anywhere."))
                point("key", L("You decide what it can read"), L("macOS asks before ORIX Clean reads Desktop, Documents or Downloads. Full Disk Access is optional; without it, protected folders are simply not counted, and the app says so."))
            }
            HStack {
                if !model.fullDiskAccess {
                    Button(L("Open Full Disk Access Settings")) { NSWorkspace.shared.open(Permissions.fullDiskAccessSettingsURL) }
                }
                Spacer()
                Button(L("Get Started"), action: done).buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.start")
            }
        }
        .padding(ORIX.Space.xxl)
        .frame(width: 600)
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: ORIX.Space.m) {
            Image(systemName: symbol).font(.title2).foregroundStyle(ORIX.Palette.accent).frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(ORIX.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
