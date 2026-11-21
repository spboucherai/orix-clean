// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/CleanupPlanner/CleanupCatalog.swift
// Description: Documented catalogue of cache, log and developer locations, each with risk, reason and consequence.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation

/// A known location. `children` means every entry inside is its own candidate.
public struct CatalogRule: Sendable {
    public var id: String
    public var category: CleanupCategory
    public var owner: String
    /// Path relative to the home directory, or absolute.
    public var path: String
    public var children: Bool
    public var risk: Risk
    public var reason: String
    public var consequence: String
    public var regeneration: String?
    public var closeFirst: [String] = []
    /// Only entries not modified for this many days are offered (0 = no age condition).
    public var minimumAgeDays = 0
}

public enum CleanupCatalog {
    public enum Section: Sendable { case caches, developer }

    /// Cache folders whose content is application state rather than a cache, or that macOS protects. Never offered.
    public static let excludedCacheNames: Set<String> = [
        "com.apple.HomeKit", "com.apple.homed", "CloudKit", "com.apple.bird", "com.apple.cloudd", "FamilyCircle", "com.apple.ap.adprivacyd",
        "com.apple.containermanagerd", "com.apple.Safari.SafeBrowsing", "com.apple.findmy.fmipcore", "com.apple.findmy.fmfcore",
        "com.apple.iCloudHelper", "GeoServices", "com.apple.AddressBookSourceSync", "com.apple.tccd", "com.apple.nsurlsessiond",
    ]

    public static func rules(_ section: Section) -> [CatalogRule] {
        switch section {
        case .caches: return cacheRules
        case .developer: return developerRules
        }
    }

    static var cacheRules: [CatalogRule] {
        let rebuilt = L("The application rebuilds it the next time it needs it; the first launches may be slower.")
        var rules: [CatalogRule] = [
            CatalogRule(id: "user-caches", category: .appCache, owner: "", path: "Library/Caches", children: true, risk: .low,
                        reason: L("Cache folder of an application in ~/Library/Caches, a location macOS reserves for recreatable data."),
                        consequence: rebuilt, regeneration: L("Rebuilt automatically")),
            CatalogRule(id: "user-logs", category: .logs, owner: "", path: "Library/Logs", children: true, risk: .low,
                        reason: L("Log files written by an application in ~/Library/Logs."),
                        consequence: L("Past diagnostic history of this application is lost. Keep it if you are investigating a problem."),
                        regeneration: L("Not regenerated; new logs start empty")),
            CatalogRule(id: "crash-reports", category: .logs, owner: L("Crash reports"), path: "Library/Logs/DiagnosticReports", children: false, risk: .low,
                        reason: L("Crash and hang reports kept for diagnostics."),
                        consequence: L("Past crash reports are no longer available to you or to a developer."), regeneration: L("Not regenerated")),
        ]
        let browsers: [(String, String, [String], String)] = [
            ("Safari", "Library/Containers/com.apple.Safari/Data/Library/Caches", ["com.apple.Safari"], "safari"),
            ("Google Chrome", "Library/Caches/Google/Chrome", ["com.google.Chrome"], "chrome"),
            ("Firefox", "Library/Caches/Firefox", ["org.mozilla.firefox"], "firefox"),
            ("Microsoft Edge", "Library/Caches/Microsoft Edge", ["com.microsoft.edgemac"], "edge"),
            ("Brave", "Library/Caches/BraveSoftware/Brave-Browser", ["com.brave.Browser"], "brave"),
            ("Arc", "Library/Caches/Arc", ["company.thebrowser.Browser"], "arc"),
            ("Opera", "Library/Caches/com.operasoftware.Opera", ["com.operasoftware.Opera"], "opera"),
            ("Vivaldi", "Library/Caches/Vivaldi", ["com.vivaldi.Vivaldi"], "vivaldi"),
        ]
        for b in browsers {
            rules.append(CatalogRule(id: "browser-" + b.3, category: .browserCache, owner: b.0, path: b.1, children: false, risk: .low,
                                     reason: L("Web cache of %@: copies of pages, images and scripts already downloaded. History, bookmarks, passwords and cookies are stored elsewhere and are not included.", b.0),
                                     consequence: L("Sites load from the network again on the next visit. You stay signed in."),
                                     regeneration: L("Rebuilt as you browse"), closeFirst: b.2))
        }
        rules.append(CatalogRule(id: "tmp-user", category: .temporary, owner: L("Temporary items"), path: NSTemporaryDirectory(), children: true, risk: .review,
                                 reason: L("Item in your temporary folder that has not been modified for 7 days or more."),
                                 consequence: L("An application that still expects this file would have to recreate it. macOS clears this folder by itself over time."),
                                 regeneration: L("Depends on the application"), minimumAgeDays: 7))
        return rules
    }

    static var developerRules: [CatalogRule] {
        func dev(_ id: String, _ owner: String, _ path: String, children: Bool = false, risk: Risk = .low, _ reason: String, _ consequence: String,
                 _ regen: String, close: [String] = []) -> CatalogRule {
            CatalogRule(id: id, category: .developer, owner: owner, path: path, children: children, risk: risk, reason: reason,
                        consequence: consequence, regeneration: regen, closeFirst: close)
        }
        let xcode = ["com.apple.dt.Xcode"]
        return [
            dev("xcode-deriveddata", "Xcode", "Library/Developer/Xcode/DerivedData", children: true,
                L("Build products, indexes and module caches of one Xcode project."),
                L("The next build of this project is a full build and the index is rebuilt."), L("Full rebuild (minutes on large projects)"), close: xcode),
            dev("xcode-archives", "Xcode", "Library/Developer/Xcode/Archives", children: true, risk: .review,
                L("Archives made with Product > Archive. They contain the dSYM files needed to symbolicate crash reports of shipped builds."),
                L("The archived builds can no longer be re-exported, and their crash reports can no longer be symbolicated from this Mac."),
                L("Cannot be regenerated identically")),
            dev("xcode-ios-devicesupport", "Xcode", "Library/Developer/Xcode/iOS DeviceSupport", children: true,
                L("Debug symbols copied from a connected device for one OS version."),
                L("Xcode copies them again (several minutes) the next time a device with this OS version is connected."), L("Copied again from the device"), close: xcode),
            dev("xcode-watchos-devicesupport", "Xcode", "Library/Developer/Xcode/watchOS DeviceSupport", children: true,
                L("Debug symbols copied from a connected device for one OS version."),
                L("Xcode copies them again (several minutes) the next time a device with this OS version is connected."), L("Copied again from the device"), close: xcode),
            dev("xcode-previews", "Xcode", "Library/Developer/Xcode/UserData/Previews", L("SwiftUI preview build products and simulator data."),
                L("Previews are rebuilt on next use."), L("Rebuilt on demand"), close: xcode),
            dev("xcode-documentation", "Xcode", "Library/Developer/Xcode/DocumentationCache", L("Compiled documentation index."),
                L("Xcode rebuilds the documentation index."), L("Rebuilt on demand"), close: xcode),
            dev("coresimulator-caches", "Simulator", "Library/Developer/CoreSimulator/Caches", L("Shared caches of the simulator runtimes (dyld caches)."),
                L("The first launch of each simulator runtime is slower while the cache is rebuilt."), L("Rebuilt on first simulator boot")),
            dev("swiftpm-cache", "Swift Package Manager", "Library/Caches/org.swift.swiftpm", L("Downloaded package repositories and manifests cache."),
                L("Packages are fetched again from their sources at the next resolution (network required)."), L("Downloaded again")),
            dev("cocoapods-cache", "CocoaPods", "Library/Caches/CocoaPods", L("Downloaded pod sources."),
                L("Pods are downloaded again at the next pod install."), L("Downloaded again")),
            dev("carthage-cache", "Carthage", "Library/Caches/org.carthage.CarthageKit", L("Carthage dependency checkouts and build cache."),
                L("Dependencies are fetched and built again."), L("Downloaded and rebuilt")),
            dev("homebrew-cache", "Homebrew", "Library/Caches/Homebrew", L("Downloaded bottles and source archives of installed formulae."),
                L("Installed software keeps working. A reinstall downloads the archive again."), L("Downloaded again")),
            dev("npm-cache", "npm", ".npm/_cacache", L("Content-addressed cache of downloaded npm packages."),
                L("Packages are downloaded again at the next npm install."), L("Downloaded again")),
            dev("yarn-cache", "Yarn", "Library/Caches/Yarn", L("Cache of downloaded Yarn packages."),
                L("Packages are downloaded again at the next install."), L("Downloaded again")),
            dev("pnpm-store", "pnpm", "Library/pnpm/store", risk: .review, L("pnpm content store. Projects link their node_modules into it."),
                L("Existing projects must run pnpm install again before they work."), L("Downloaded again; projects need reinstalling")),
            dev("pip-cache", "pip", "Library/Caches/pip", L("Cache of downloaded and built Python wheels."),
                L("Wheels are downloaded or built again at the next pip install."), L("Downloaded again")),
            dev("uv-cache", "uv", ".cache/uv", risk: .review, L("uv package cache. Environments created by uv may link files into it."),
                L("Packages are downloaded again; environments that link into the cache may need to be recreated."), L("Downloaded again")),
            dev("gradle-caches", "Gradle", ".gradle/caches", L("Downloaded dependencies and build caches of Gradle."),
                L("The next Gradle build downloads dependencies again and starts cold."), L("Downloaded again")),
            dev("maven-repository", "Maven", ".m2/repository", risk: .review, L("Local Maven repository. It also holds artifacts you installed locally with mvn install."),
                L("Remote dependencies are downloaded again. Locally installed artifacts are lost until rebuilt."), L("Remote: downloaded again. Local artifacts: rebuild")),
            dev("cargo-registry", "Cargo", ".cargo/registry", L("Downloaded crate archives and their extracted sources."),
                L("Crates are downloaded again at the next build."), L("Downloaded again")),
            dev("go-build", "Go", "Library/Caches/go-build", L("Go build cache."), L("The next go build recompiles everything."), L("Rebuilt")),
            dev("go-modcache", "Go", "go/pkg/mod", risk: .review, L("Go module cache (read-only files)."),
                L("Modules are downloaded again. Offline builds fail until then."), L("Downloaded again")),
            dev("playwright-browsers", "Playwright", "Library/Caches/ms-playwright", L("Browser binaries downloaded by Playwright."),
                L("Playwright downloads the browsers again at the next install."), L("Downloaded again")),
            dev("android-avd-cache", "Android", ".android/cache", L("Android SDK tool cache."), L("Recreated by the Android tools."), L("Rebuilt")),
        ]
    }

    /// Locations that are reported for information only, with the supported way to clean them.
    public struct ManualHint: Sendable, Identifiable, Hashable {
        public var id: String { path }
        public var owner: String
        public var path: String
        public var measurement: Measurement
        public var guidance: String
    }

    public static func manualHints(home: String = NSHomeDirectory()) -> [ManualHint] {
        let list: [(String, String, String)] = [
            (L("Simulator devices"), "Library/Developer/CoreSimulator/Devices",
             L("Simulators hold installed apps and their data. Remove the ones you no longer need in Xcode > Window > Devices and Simulators, or run: xcrun simctl delete unavailable")),
            ("Docker", "Library/Containers/com.docker.docker/Data/vms",
             L("The Docker disk image holds your images, containers and volumes. Reduce it from Docker Desktop, or run: docker system prune")),
            (L("Xcode simulator runtimes"), "/Library/Developer/CoreSimulator/Volumes",
             L("Simulator runtimes are managed in Xcode > Settings > Components. ORIX Clean does not remove toolchains or runtimes.")),
        ]
        return list.compactMap { owner, rel, text in
            let path = rel.hasPrefix("/") ? rel : home + "/" + rel
            guard let m = Measure.item(path), m.allocated > 0 else { return nil }
            return ManualHint(owner: owner, path: path, measurement: m, guidance: text)
        }
    }

    /// Finds what exists on disk for a section and measures it. Blocking.
    public static func discover(_ section: Section, home: String = NSHomeDirectory(), minimumSize: Int64 = 64 * 1024,
                                appNames: [String: String] = [:], isCancelled: () -> Bool = { false }) -> [CleanupItem] {
        var items: [CleanupItem] = []
        var claimed = Set<String>()
        let all = rules(section)
        // Specific rules claim their path first so the generic "children of ~/Library/Caches" rule does not list it twice.
        for rule in all where !rule.children {
            claimed.insert(rule.path.hasPrefix("/") ? (rule.path as NSString).standardizingPath : home + "/" + rule.path)
        }
        let developerPaths = Set(developerRules.map { home + "/" + $0.path })
        let now = Date()
        for rule in all {
            if isCancelled() { break }
            let base = rule.path.hasPrefix("/") ? (rule.path as NSString).standardizingPath : home + "/" + rule.path
            var targets: [String] = []
            if rule.children {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
                for name in names.sorted() where name != ".DS_Store" && name != ".localized" {
                    let p = base + "/" + name
                    if claimed.contains(p) || claimed.contains(where: { $0.hasPrefix(p + "/") }) { continue }
                    if rule.id == "user-caches" {
                        if excludedCacheNames.contains(name) || name.hasPrefix("com.apple.") { continue }
                        if section == .caches, developerPaths.contains(p) { continue }
                    }
                    if rule.id == "user-logs", name == "DiagnosticReports" { continue }
                    targets.append(p)
                }
            } else {
                targets = [base]
            }
            for path in targets {
                if isCancelled() { break }
                guard let m = Measure.item(path), m.allocated >= minimumSize else { continue }
                if rule.minimumAgeDays > 0, let modified = m.modified, now.timeIntervalSince(modified) < Double(rule.minimumAgeDays) * 86400 { continue }
                var owner = rule.owner
                var close = rule.closeFirst
                if owner.isEmpty {
                    let name = (path as NSString).lastPathComponent
                    owner = appNames[name] ?? name
                    if appNames[name] != nil { close = [name] }
                }
                items.append(CleanupItem(path: path, category: rule.category, risk: rule.risk, reason: rule.reason, consequence: rule.consequence,
                                         measurement: m, owner: owner, regeneration: rule.regeneration, closeFirst: close))
            }
        }
        return items.sorted { $0.measurement.allocated > $1.measurement.allocated }
    }

    /// Build output folders found inside a scanned tree (node_modules, .build, target, DerivedData), each next to its manifest.
    public static func buildArtifacts(in tree: ScanTree, minimumSize: Int64 = 20 * 1024 * 1024) -> [CleanupItem] {
        let wanted: [String: (manifest: [String], owner: String, regen: String)] = [
            "node_modules": (["package.json"], "Node.js", L("Reinstalled with npm, yarn or pnpm install")),
            ".build": (["Package.swift"], "Swift Package Manager", L("Rebuilt by swift build")),
            "target": (["Cargo.toml", "pom.xml"], "Cargo / Maven", L("Rebuilt by the next build")),
            "DerivedData": ([], "Xcode", L("Rebuilt by Xcode")),
            ".gradle": (["build.gradle", "build.gradle.kts", "settings.gradle"], "Gradle", L("Recreated by Gradle")),
            "__pycache__": ([], "Python", L("Recreated when the modules are imported")),
        ]
        var items: [CleanupItem] = []
        var stack: [Int32] = [0]
        while let i = stack.popLast() {
            let n = tree[i]
            guard n.flags.contains(.directory), !n.flags.contains(.removed), !n.flags.contains(.package) else { continue }
            var names: [String: Int32] = [:]
            for c in tree.children(of: i) { names[tree.name(of: c)] = c }
            for (name, c) in names {
                let child = tree[c]
                guard child.flags.contains(.directory) else { continue }
                if let rule = wanted[name], rule.manifest.isEmpty || rule.manifest.contains(where: { names[$0] != nil }) {
                    if child.allocatedSize >= minimumSize, name != "__pycache__" || child.allocatedSize >= minimumSize {
                        let path = tree.path(of: c)
                        if path.contains("/Library/") { continue }
                        var m = Measurement()
                        m.logical = child.logicalSize; m.allocated = child.allocatedSize; m.privateSize = child.privateSize
                        m.files = Int(child.fileCount); m.isDirectory = true; m.fileID = child.fileID
                        m.modified = Date(timeIntervalSince1970: TimeInterval(child.modified))
                        items.append(CleanupItem(path: path, category: .developer, risk: .review,
                                                 reason: L("Build or dependency folder (%@) found next to its project manifest.", name),
                                                 consequence: L("The project must reinstall or rebuild before it runs again. If the project is active, wait until you are done."),
                                                 measurement: m, owner: rule.owner, regeneration: rule.regen))
                    }
                    continue
                }
                if !name.hasPrefix(".") || name == ".build" { stack.append(c) }
            }
        }
        return items.sorted { $0.measurement.allocated > $1.measurement.allocated }
    }
}
