// ORIX Clean — Packages/ORIXCleanCore/Tests/ORIXCleanCoreTests/CleanupTests.swift
// Description: Safety policy, deletion engine, catalog, downloads, trash, applications, history, reports and workflows.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation
import Testing
@testable import ORIXCleanCore

@Suite struct SafetyPolicyTests {
    let policy = SafetyPolicy(home: "/Users/tester")

    @Test func protectedLocationsAreDenied() {
        for p in ["/", "/System", "/System/Library/CoreServices", "/usr/bin/zip", "/bin", "/Library", "/Library/Preferences", "/Applications",
                  "/Users", "/Users/tester", "/Users/other", "/Users/tester/Documents", "/Users/tester/Desktop", "/Users/tester/Library",
                  "/Users/tester/Library/Caches", "/Users/tester/Library/Application Support", "/Users/tester/Library/Keychains/login.keychain-db",
                  "/Volumes", "/Volumes/Backup", "/private/var/db/receipts", "/etc/hosts", "/var/root", "/System/Applications/Mail.app",
                  "/Applications/Safari.app/Contents/MacOS/Safari", "/Users/tester/Pictures/Photos Library.photoslibrary/database/Photos.sqlite",
                  "/System/Volumes/Data/Users/tester/Documents", "relative/path", "/Users/tester/Documents/../Library", "/Users/tester/.Trash",
                  "/private/tmp", "/tmp", "/Volumes/Backup/.Trashes", "/Volumes/Backup/.Trashes/501", "/private/var/folders/ab/cdef/T",
                  "/var/folders/ab/cdef", "/Users/tester/.ssh", "/Users/tester/.ssh/id_ed25519", "/Users/tester/.gnupg/pubring.kbx", "/Users/tester/.aws/credentials"] {
            #expect(policy.evaluate(p) != .allowed, "\(p) must be protected")
        }
    }

    @Test func ordinaryItemsAreAllowed() {
        for p in ["/Users/tester/Downloads/installer.dmg", "/Users/tester/Library/Caches/com.vendor.app", "/Users/tester/Documents/old/report.pdf",
                  "/Applications/Vendor.app", "/Users/tester/Library/Developer/Xcode/DerivedData/App-abc", "/Users/tester/.npm/_cacache",
                  "/Users/tester/project", "/Users/tester/.Trash/old.zip", "/Volumes/Backup/folder/file.bin", "/private/tmp/scratch",
                  "/private/var/folders/ab/cdef/T/item", "/Users/tester/Pictures/Photos Library.photoslibrary", "/Volumes/Backup/.Trashes/501/x"] {
            #expect(policy.evaluate(p) == .allowed, "\(p) should be allowed")
        }
    }
}

@Suite struct DeletionTests {
    func engine(_ s: Sandbox, failing: Set<String> = [], error: NSError? = nil) -> DeletionEngine {
        var t = FakeTrasher(bin: s.dir("bin"))
        t.failing = failing
        if let error { t.error = error }
        return DeletionEngine(policy: SafetyPolicy(home: s.path("home")), trasher: t)
    }

    @Test func nothingIsRemovedWithoutAuthorization() {
        let s = Sandbox()
        let a = s.file("a.bin", size: 1000), b = s.file("b.bin", size: 2000)
        let confirmed = CleanupPlan(items: [item(a)])
        let auth = CleanupAuthorization(confirming: confirmed, highRiskAcknowledged: false)
        let r = engine(s).execute(plan: CleanupPlan(items: [item(a), item(b)]), authorization: auth)
        #expect(r.count(.movedToTrash) == 1 && r.count(.skipped) == 1)
        #expect(!FileManager.default.fileExists(atPath: a))
        #expect(FileManager.default.fileExists(atPath: b))
    }

    @Test func highRiskNeedsExplicitAcknowledgement() {
        let s = Sandbox()
        let a = s.file("a.bin", size: 1000)
        let plan = CleanupPlan(items: [item(a, risk: .high)])
        let r1 = engine(s).execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false))
        #expect(r1.count(.skipped) == 1 && FileManager.default.fileExists(atPath: a))
        let r2 = engine(s).execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: true))
        #expect(r2.count(.movedToTrash) == 1)
    }

    @Test func moveToTheRealTrashAndRestore() throws {
        let s = Sandbox()
        let a = s.file("folder/keepsake.bin", size: 123_456, seed: 4)
        let digest = DuplicateFinder.fullHash(path: a)
        let plan = CleanupPlan(items: [item(s.path("folder"))])
        let real = DeletionEngine(policy: SafetyPolicy())
        let r = real.execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false))
        #expect(r.count(.movedToTrash) == 1)
        #expect(!FileManager.default.fileExists(atPath: a))
        let rec = try #require(r.records.first)
        let trashPath = try #require(rec.trashPath)
        #expect(FileManager.default.fileExists(atPath: trashPath))
        #expect(real.restore(rec) == .restored)
        #expect(DuplicateFinder.fullHash(path: a) == digest)
        #expect(real.restore(rec) == .notInTrash)
    }

    @Test func restoreRefusesToOverwrite() throws {
        let s = Sandbox()
        let a = s.file("a.bin", size: 100)
        let e = engine(s)
        let plan = CleanupPlan(items: [item(a)])
        let r = e.execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false))
        s.file("a.bin", size: 5)
        #expect(e.restore(r.records[0]) == .destinationOccupied)
    }

    @Test func revalidationSkipsVanishedReplacedAndChangedItems() {
        let s = Sandbox()
        let gone = s.file("gone.bin", size: 100), changed = s.file("changed.bin", size: 100), replaced = s.file("replaced.bin", size: 100)
        let plan = CleanupPlan(items: [item(gone), item(changed), item(replaced)])
        try? FileManager.default.removeItem(atPath: gone)
        FileManager.default.createFile(atPath: s.path("tmp"), contents: Data(count: 100))
        try? FileManager.default.removeItem(atPath: replaced)
        try? FileManager.default.moveItem(atPath: s.path("tmp"), toPath: replaced)
        let h = FileHandle(forWritingAtPath: changed)!; h.seekToEndOfFile(); h.write(Data(count: 7)); try? h.close()
        let r = engine(s).execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false))
        #expect(r.count(.skipped) == 3 && r.count(.movedToTrash) == 0)
        #expect(FileManager.default.fileExists(atPath: changed) && FileManager.default.fileExists(atPath: replaced))
    }

    @Test func duplicatesAreVerifiedAgainstTheKeptCopy() {
        let s = Sandbox()
        let keep = s.file("keep.bin", size: 50_000, seed: 1), dup = s.file("dup.bin", size: 50_000, seed: 1)
        let drift = s.file("drift.bin", size: 50_000, seed: 1), orphan = s.file("orphan.bin", size: 50_000, seed: 1)
        let linked = s.path("linked.bin"); link(keep, linked)
        let items = [item(dup, category: .duplicate, verify: keep), item(drift, category: .duplicate, verify: keep),
                     item(orphan, category: .duplicate, verify: s.path("missing.bin")), item(linked, category: .duplicate, verify: keep)]
        // Same size, different content after the scan.
        let fd = open(drift, O_WRONLY); var b: UInt8 = 0x42; pwrite(fd, &b, 1, 25_000); close(fd)
        let plan = CleanupPlan(items: items)
        let r = engine(s).execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false))
        let status = Dictionary(uniqueKeysWithValues: r.records.map { (($0.path as NSString).lastPathComponent, $0.status) })
        #expect(status["dup.bin"] == .movedToTrash)
        #expect(status["drift.bin"] == .skipped && status["orphan.bin"] == .skipped && status["linked.bin"] == .skipped)
        #expect(FileManager.default.fileExists(atPath: keep))
    }

    @Test func aGroupIsNeverEmptied() {
        let s = Sandbox()
        let a = s.file("a.bin", size: 9000, seed: 1), b = s.file("b.bin", size: 9000, seed: 1)
        let plan = CleanupPlan(items: [item(a, category: .duplicate, verify: b), item(b, category: .duplicate, verify: a)])
        let r = engine(s).execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false))
        #expect(r.count(.movedToTrash) == 0)
        #expect(FileManager.default.fileExists(atPath: a) && FileManager.default.fileExists(atPath: b))
    }

    @Test func partialFailureIsReportedPerItem() {
        let s = Sandbox()
        let ok = s.file("ok.bin", size: 100), denied = s.file("denied.bin", size: 100), noTrash = s.file("notrash.bin", size: 100)
        let plan = CleanupPlan(items: [item(ok), item(denied), item(noTrash)])
        let r = engine(s, failing: [denied]).execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false))
        #expect(r.count(.movedToTrash) == 2 && r.count(.failed) == 1)
        #expect(r.records.count == 3)
        let unsupported = NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError)
        let plan2 = CleanupPlan(items: [item(denied)])
        let r2 = engine(s, failing: [denied], error: unsupported).execute(plan: plan2, authorization: CleanupAuthorization(confirming: plan2, highRiskAcknowledged: false))
        // No Trash on the volume: the item is left in place, never silently deleted for good.
        #expect(r2.count(.requiresManualAction) == 1 && FileManager.default.fileExists(atPath: denied))
    }

    @Test func protectedPathsRunningAppsPermanentModeAndCancellation() {
        let s = Sandbox()
        let home = s.dir("home")
        let docs = s.dir("home/Documents")
        let cache = s.file("home/Library/Caches/com.x.app/data", size: 500)
        let e = engine(s)
        let whole = CleanupPlan(items: [item(home)])
        #expect(e.execute(plan: whole, authorization: CleanupAuthorization(confirming: whole, highRiskAcknowledged: true)).count(.skipped) == 1)
        let plan = CleanupPlan(items: [item(docs), item(s.path("home/Library")), item((cache as NSString).deletingLastPathComponent, close: ["com.x.app"])])
        let auth = CleanupAuthorization(confirming: plan, highRiskAcknowledged: true)
        let r = e.execute(plan: plan, authorization: auth, runningBundleIDs: ["com.x.app"])
        #expect(r.count(.skipped) == 2 && r.count(.requiresManualAction) == 0)
        let busy = CleanupPlan(items: [item((cache as NSString).deletingLastPathComponent, close: ["com.x.app"])])
        #expect(e.execute(plan: busy, authorization: CleanupAuthorization(confirming: busy, highRiskAcknowledged: true), runningBundleIDs: ["com.x.app"]).count(.requiresManualAction) == 1)
        #expect(FileManager.default.fileExists(atPath: docs) && FileManager.default.fileExists(atPath: cache))
        // Permanent deletion is refused outside the Trash category.
        let p2 = CleanupPlan(items: [item((cache as NSString).deletingLastPathComponent)])
        let r2 = e.execute(plan: p2, authorization: CleanupAuthorization(confirming: p2, highRiskAcknowledged: true), mode: .permanent)
        #expect(r2.count(.skipped) == 1 && FileManager.default.fileExists(atPath: cache))
        let outside = CleanupPlan(items: [item(s.file("t.bin", size: 10), category: .trash)])
        #expect(e.execute(plan: outside, authorization: CleanupAuthorization(confirming: outside, highRiskAcknowledged: true), mode: .permanent).count(.skipped) == 1)
        let p3 = CleanupPlan(items: [item(s.file("home/.Trash/t.bin", size: 10), category: .trash)])
        let r3 = e.execute(plan: p3, authorization: CleanupAuthorization(confirming: p3, highRiskAcknowledged: true), mode: .permanent)
        #expect(r3.count(.permanentlyDeleted) == 1)
        let cancelled = engine(s); cancelled.cancel()
        let p4 = CleanupPlan(items: [item(s.file("c.bin", size: 10))])
        let r4 = cancelled.execute(plan: p4, authorization: CleanupAuthorization(confirming: p4, highRiskAcknowledged: true))
        #expect(r4.cancelled && r4.count(.skipped) == 1 && FileManager.default.fileExists(atPath: s.path("c.bin")))
    }

    @Test func readOnlyVolumeFailsCleanlyAndFullVolumeStillTrashes() throws {
        guard let ro = TestVolume(readOnlyAfter: { FileManager.default.createFile(atPath: $0 + "/frozen.bin", contents: Data(count: 4096)) }) else {
            Issue.record("hdiutil unavailable"); return
        }
        let frozen = ro.mountPoint + "/frozen.bin"
        let plan = CleanupPlan(items: [item(frozen)])
        let real = DeletionEngine(policy: SafetyPolicy())
        let r = real.execute(plan: plan, authorization: CleanupAuthorization(confirming: plan, highRiskAcknowledged: false))
        #expect(r.count(.movedToTrash) == 0)
        #expect(r.count(.failed) + r.count(.requiresManualAction) == 1)
        #expect(FileManager.default.fileExists(atPath: frozen))

        guard let full = TestVolume(sizeMB: 12) else { Issue.record("hdiutil unavailable"); return }
        let victim = full.mountPoint + "/victim.bin"
        FileManager.default.createFile(atPath: victim, contents: Data(count: 200_000))
        // Fill the volume.
        let fd = open(full.mountPoint + "/filler.bin", O_CREAT | O_WRONLY, 0o644)
        let block = [UInt8](repeating: 0xAB, count: 1 << 20)
        while write(fd, block, block.count) == block.count {}
        close(fd)
        let p2 = CleanupPlan(items: [item(victim)])
        let r2 = real.execute(plan: p2, authorization: CleanupAuthorization(confirming: p2, highRiskAcknowledged: false))
        // Moving to the Trash is a rename on the same volume: it works with no free space, and frees nothing by itself.
        #expect(r2.count(.movedToTrash) == 1)
        #expect(r2.records.first?.trashPath?.contains("-mnt/.Trashes/") == true)
        let trash = TrashAnalyzer.locations(home: "/nonexistent", volumes: [Volumes.info(for: URL(fileURLWithPath: full.mountPoint))!])
        #expect(trash.first?.items.count == 1)
        #expect(trash.first?.logical == 200_000)
    }

    @Test func planDeduplicatesNestedItems() {
        let s = Sandbox()
        s.file("d/a.bin", size: 5000); s.file("d/sub/b.bin", size: 7000)
        let plan = CleanupPlan(items: [item(s.path("d/sub/b.bin")), item(s.path("d")), item(s.path("d")), item(s.path("d/a.bin"))])
        #expect(plan.items.count == 1)
        #expect(plan.logicalSize == 12_000 && plan.fileCount == 2)
        #expect(plan.recoverable.maximum == plan.allocatedSize)
    }
}

@Suite struct CatalogTests {
    func home() -> Sandbox {
        let s = Sandbox("home")
        s.file("Library/Caches/com.vendor.editor/blob", size: 300_000)
        s.file("Library/Caches/com.apple.Safari/blob", size: 300_000)
        s.file("Library/Caches/CloudKit/blob", size: 300_000)
        s.file("Library/Caches/tiny/blob", size: 100)
        s.file("Library/Caches/Google/Chrome/Default/Cache/data", size: 400_000)
        s.file("Library/Caches/Homebrew/downloads/pkg.tar.gz", size: 500_000)
        s.file("Library/Logs/Vendor/app.log", size: 200_000)
        s.file("Library/Developer/Xcode/DerivedData/App-aaaa/Build/x.o", size: 800_000)
        s.file("Library/Developer/Xcode/DerivedData/Lib-bbbb/Build/y.o", size: 700_000)
        s.file("Library/Developer/Xcode/Archives/2020-01-01/App.xcarchive/Info.plist", size: 900_000)
        s.file(".npm/_cacache/content/z", size: 600_000)
        return s
    }

    @Test func cachesSectionListsOnlyDocumentedSafeLocations() {
        let s = home()
        let items = CleanupCatalog.discover(.caches, home: s.root, appNames: ["com.vendor.editor": "Editor"])
        let names = Set(items.map { $0.path.replacingOccurrences(of: s.root + "/", with: "") })
        #expect(names.contains("Library/Caches/com.vendor.editor"))
        #expect(names.contains("Library/Caches/Google/Chrome"))
        #expect(names.contains("Library/Logs/Vendor"))
        #expect(!names.contains { $0.contains("com.apple.") || $0.contains("CloudKit") || $0.contains("tiny") || $0.contains("Homebrew") })
        let editor = items.first { $0.path.hasSuffix("com.vendor.editor") }!
        #expect(editor.owner == "Editor" && editor.closeFirst == ["com.vendor.editor"] && editor.risk == .low)
        #expect(editor.measurement.logical == 300_000 && !editor.reason.isEmpty && !editor.consequence.isEmpty)
        let chrome = items.first { $0.path.hasSuffix("Google/Chrome") }!
        #expect(chrome.category == .browserCache && chrome.closeFirst == ["com.google.Chrome"])
        let policy = SafetyPolicy(home: s.root)
        #expect(items.allSatisfy { policy.evaluate($0.path) == .allowed })
    }

    @Test func developerSectionSplitsPerProjectAndMarksArchivesForReview() {
        let s = home()
        let items = CleanupCatalog.discover(.developer, home: s.root)
        let derived = items.filter { $0.path.contains("DerivedData/") }
        #expect(derived.count == 2 && derived.allSatisfy { $0.risk == .low && $0.closeFirst == ["com.apple.dt.Xcode"] && $0.regeneration != nil })
        #expect(items.first { $0.path.contains("Archives/") }?.risk == .review)
        #expect(items.contains { $0.path.hasSuffix(".npm/_cacache") && $0.owner == "npm" })
        #expect(items.contains { $0.path.hasSuffix("Library/Caches/Homebrew") })
        let policy = SafetyPolicy(home: s.root)
        #expect(items.allSatisfy { policy.evaluate($0.path) == .allowed })
    }

    @Test func everyRuleIsDocumented() {
        for rule in CleanupCatalog.rules(.caches) + CleanupCatalog.rules(.developer) {
            #expect(!rule.reason.isEmpty && !rule.consequence.isEmpty && rule.regeneration != nil, "\(rule.id)")
        }
        #expect(Set((CleanupCatalog.rules(.caches) + CleanupCatalog.rules(.developer)).map(\.id)).count == CleanupCatalog.rules(.caches).count + CleanupCatalog.rules(.developer).count)
    }

    @Test func buildArtifactsNeedTheirManifest() throws {
        let s = Sandbox()
        s.text("web/package.json", "{}"); s.file("web/node_modules/lib/index.js", size: 300_000)
        s.file("stray/node_modules/lib/index.js", size: 300_000)
        s.text("pkg/Package.swift", "//"); s.file("pkg/.build/debug/x.o", size: 300_000)
        s.file("docs/target/notes.bin", size: 300_000)
        let items = CleanupCatalog.buildArtifacts(in: try s.scan().tree, minimumSize: 1000)
        #expect(Set(items.map { $0.path.replacingOccurrences(of: s.root + "/", with: "") }) == ["web/node_modules", "pkg/.build"])
        #expect(items.allSatisfy { $0.risk == .review })
    }

    @Test func downloadsAreClassified() throws {
        let s = Sandbox()
        s.file("Downloads/App.dmg", size: 90_000); s.file("Downloads/Setup.pkg", size: 80_000)
        s.file("Downloads/photos.zip", size: 70_000); s.file("Downloads/photos/1.jpg", size: 10_000)
        s.file("Downloads/movie.mp4.crdownload", size: 60_000); s.file("Downloads/notes.txt", size: 100)
        s.text("Downloads/.hidden", "x")
        let entries = try DownloadsAnalyzer.analyze(folder: s.path("Downloads"))
        let kinds = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.kind) })
        #expect(kinds == ["App.dmg": .diskImage, "Setup.pkg": .installer, "photos.zip": .archive, "photos": .other,
                          "movie.mp4.crdownload": .partial, "notes.txt": .other])
        #expect(entries.first { $0.name == "photos.zip" }?.extractedSibling == "photos")
        let ci = entries.first { $0.name == "photos.zip" }!.cleanupItem()
        #expect(ci.risk == .review && ci.category == .archive && ci.reason.contains("photos"))
    }

    @Test func trashInventory() {
        let s = Sandbox()
        s.file(".Trash/old.zip", size: 40_000); s.file(".Trash/folder/a.bin", size: 60_000)
        let t = TrashAnalyzer.locations(home: s.root, volumes: [])
        #expect(t.count == 1 && t[0].accessible && t[0].items.count == 2)
        #expect(t[0].logical == 100_000 && t[0].fileCount == 2)
        #expect(t[0].items[0].cleanupItem.category == .trash)
        chmod(s.path(".Trash"), 0)
        #expect(TrashAnalyzer.locations(home: s.root, volumes: []).first?.accessible == false)
        chmod(s.path(".Trash"), 0o700)
    }
}

@Suite struct ApplicationTests {
    func makeApp(_ s: Sandbox, _ name: String, id: String) -> String {
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": "2.1", "CFBundleVersion": "42",
                                    "CFBundleExecutable": name, "CFBundlePackageType": "APPL"]
        let dir = s.dir("Applications/\(name).app/Contents")
        try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: URL(fileURLWithPath: dir + "/Info.plist"))
        s.file("Applications/\(name).app/Contents/MacOS/\(name)", size: 150_000)
        return s.path("Applications/\(name).app")
    }

    @Test func discoveryAssociatedFilesAndUninstallPlan() throws {
        let s = Sandbox()
        _ = makeApp(s, "Sketcher", id: "com.vendor.sketcher")
        s.file("Library/Application Support/com.vendor.sketcher/db.sqlite", size: 70_000)
        s.file("Library/Application Support/Sketcher/assets.bin", size: 60_000)
        s.file("Library/Application Support/Sketcher Pro/other.bin", size: 60_000)
        s.file("Library/Caches/com.vendor.sketcher/c", size: 50_000)
        s.file("Library/Caches/com.vendor.sketcher.helper/c", size: 20_000)
        s.text("Library/Preferences/com.vendor.sketcher.plist", "p")
        s.text("Library/Preferences/com.vendor.sketcherx.plist", "p")
        s.file("Library/Saved Application State/com.vendor.sketcher.savedState/w", size: 1000)
        s.file("Documents/Drawing.sketch", size: 1000)
        let apps = AppInventory.discover(directories: [s.path("Applications")])
        #expect(apps.count == 1)
        let app = AppInventory.measure(apps[0])
        #expect(app.name == "Sketcher" && app.bundleID == "com.vendor.sketcher" && app.version == "2.1" && app.build == "42" && !app.isSystem)
        #expect(app.measurement?.logical ?? 0 > 150_000)
        #expect(app.signature?.kind == .unsigned)
        let files = AppInventory.associatedFiles(for: app, home: s.root)
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.path.replacingOccurrences(of: s.root + "/Library/", with: ""), $0.confidence) })
        #expect(byName == ["Application Support/com.vendor.sketcher": .identifier, "Application Support/Sketcher": .nameMatch,
                           "Caches/com.vendor.sketcher": .identifier, "Caches/com.vendor.sketcher.helper": .identifier,
                           "Preferences/com.vendor.sketcher.plist": .identifier, "Saved Application State/com.vendor.sketcher.savedState": .identifier])
        let items = AppInventory.uninstallItems(app: app, files: files)
        #expect(items.count == 7)
        #expect(items.first?.category == .application)
        #expect(items.first { $0.path.hasSuffix("Support/Sketcher") }?.risk == .high)
        #expect(!items.contains { $0.path.contains("Documents") })
        #expect(items.allSatisfy { $0.closeFirst == ["com.vendor.sketcher"] })
    }

    @Test func systemApplicationsAreNeverOffered() {
        let mail = AppInventory.read("/System/Applications/Mail.app")
        #expect(mail?.isSystem == true)
        #expect(AppInventory.uninstallItems(app: mail!, files: []).isEmpty)
        let sig = AppInventory.signature(of: "/System/Applications/Mail.app")
        #expect(sig.kind == .apple && sig.valid)
    }

    @Test func leftoversAreInferredConservatively() {
        let s = Sandbox()
        let app = AppInventory.read(makeApp(s, "Sketcher", id: "com.vendor.sketcher"))!
        s.file("Library/Application Support/com.gone.oldapp/data", size: 90_000)
        s.file("Library/Caches/com.vendor.sketcher/c", size: 90_000)
        s.file("Library/Caches/com.vendor.shared/c", size: 90_000)
        s.file("Library/Caches/com.apple.something/c", size: 90_000)
        s.file("Library/Caches/org.registered.tool/c", size: 90_000)
        s.file("Library/Application Support/Plain Name/c", size: 90_000)
        s.file("Library/Preferences/com.gone.oldapp.plist", size: 30_000)
        let found = LeftoverFinder.find(installed: [app], home: s.root, resolver: { $0 == "org.registered.tool" })
        #expect(Set(found.map(\.identifier)) == ["com.gone.oldapp"])
        #expect(found.count == 2)
        #expect(found[0].cleanupItem.risk == .review && found[0].cleanupItem.confidenceNote != nil)
    }
}

@Suite struct HistoryAndReportTests {
    func volume(_ available: Int64) -> VolumeInfo {
        VolumeInfo(path: "/", name: "Macintosh HD", uuid: "UUID-1", format: "apfs", total: 1_000_000_000_000, available: available,
                   availableForImportantUsage: available, isInternal: true, isRemovable: false, isReadOnly: false, isStartup: true, isNetwork: false)
    }

    @Test func historyStoreRoundTrip() throws {
        let s = Sandbox()
        let store = try HistoryStore(path: s.path("db/history.sqlite"))
        #expect(store.monitoringStart() == nil)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for d in 0 ..< 10 { store.record(volume: volume(500_000_000_000 - Int64(d) * 2_000_000_000), at: t0.addingTimeInterval(Double(d) * 86400)) }
        store.record(volume: volume(500_000_000_000 - 18_000_000_000), at: t0.addingTimeInterval(9 * 86400 + 60))
        let samples = store.volumeSamples(volumeID: "UUID-1", since: nil)
        #expect(samples.count == 10)
        #expect(store.monitoringStart() == t0)
        let slope = try #require(Trend.bytesPerDay(samples))
        #expect(abs(slope - 2_000_000_000) < 1_000_000)
        #expect(Trend.bytesPerDay(Array(samples.prefix(2))) == nil)
        store.watch("/a"); store.watch("/a"); store.watch("/b"); store.unwatch("/b")
        #expect(store.watched() == ["/a"])
        var m = Measurement(); m.logical = 5; m.allocated = 4096; m.files = 1
        store.record(folder: "/a", measurement: m, at: t0)
        #expect(store.folderSamples(path: "/a").first?.allocated == 4096)
        let rec = DeletionRecord(path: "/x", status: .movedToTrash, detail: "d", trashPath: "/t", logicalSize: 1, allocatedSize: 2, category: .appCache)
        let report = DeletionReport(id: UUID(), started: t0, finished: t0, mode: .moveToTrash, records: [rec], cancelled: false, freeBefore: 1, freeAfter: 2)
        store.save(report)
        #expect(store.operations() == [report])
        store.saveDocument(Workflow(id: "w1", name: "Mine", steps: [.collectCaches, .review, .moveToTrash]), kind: "workflow", id: "w1")
        #expect(store.documents(Workflow.self, kind: "workflow").first?.name == "Mine")
        // Reopen: data persisted.
        #expect(try HistoryStore(path: s.path("db/history.sqlite")).volumeSamples(volumeID: "UUID-1", since: t0.addingTimeInterval(5 * 86400)).count == 5)
        store.eraseAll()
        #expect(store.monitoringStart() == nil && store.operations().isEmpty)
    }

    @Test func recommendationsComeOnlyFromEvidence() {
        var f = Findings()
        #expect(RecommendationEngine.evaluate(f).isEmpty)
        f.volumes = [volume(50_000_000_000)]
        let low = RecommendationEngine.evaluate(f)
        #expect(low.count == 1 && low[0].id.hasPrefix("low-space") && low[0].evidence.contains("5"))
        f.volumes = [volume(500_000_000_000)]
        var m = Measurement(); m.allocated = 4_000_000_000; m.logical = 4_000_000_000; m.isDirectory = true
        f.developer = (0 ..< 2).map { CleanupItem(path: "/Users/t/Library/Developer/Xcode/DerivedData/P\($0)", category: .developer, risk: .low, reason: "r", consequence: "c", measurement: m) }
        f.caches = []
        let recs = RecommendationEngine.evaluate(f)
        #expect(recs.map(\.id) == ["deriveddata"])
        #expect(recs[0].measuredSize == 8_000_000_000 && recs[0].paths.count == 2)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        f.history = ["UUID-1": (0 ..< 8).map { VolumeSample(date: t0.addingTimeInterval(Double($0) * 86400), volumeID: "UUID-1", name: "M", total: 1_000_000_000_000, available: 500_000_000_000 - Int64($0) * 20_000_000_000) }]
        #expect(RecommendationEngine.evaluate(f).contains { $0.id == "growth-UUID-1" })
    }

    @Test func reportRenderers() throws {
        let s = Sandbox()
        s.file("r/big.bin", size: 400_000); s.file("r/a|b,\"q\".txt", size: 1000); s.text("r/=cmd.txt", "x")
        let result = try s.scan("r")
        var sections = ReportBuilder.overview(result: result, volume: Volumes.containing(s.root))
        sections += ReportBuilder.duplicates(DuplicateFinder().run(tree: result.tree))
        sections.append(ReportSection(title: "Formula", headers: ["Path"], rows: [["=HYPERLINK(\"x\")"], ["+1"], ["normal"]]))
        let report = Report(title: "Storage overview", scope: s.path("r"),
                            limitations: ReportBuilder.limitations(issues: result.issues, fullDiskAccess: false, sharingMeasured: true), sections: sections, appVersion: "1.0.0")
        let md = String(decoding: report.render(.markdown), as: UTF8.self)
        #expect(md.hasPrefix("# Storage overview") && md.contains("big.bin") && md.contains("a\\|b") && md.contains("Full Disk Access"))
        let csv = String(decoding: report.render(.csv), as: UTF8.self)
        #expect(csv.contains("\"'=HYPERLINK(\"\"x\"\")\"") && csv.contains("\"'+1\"") && csv.contains("\"normal\""))
        #expect(csv.contains("a|b,\"\"q\"\".txt"))
        let json = try JSONSerialization.jsonObject(with: report.render(.json)) as? [String: Any]
        #expect(json?["title"] as? String == "Storage overview" && (json?["sections"] as? [Any])?.count == sections.count)
        let pdf = report.render(.pdf)
        #expect(pdf.prefix(5) == Data("%PDF-".utf8) && pdf.count > 3000)
        let rec = DeletionRecord(path: "/x", status: .failed, detail: "Permission denied", trashPath: nil, logicalSize: 1, allocatedSize: 4096, category: .appCache)
        let del = DeletionReport(id: UUID(), started: Date(), finished: Date(), mode: .moveToTrash, records: [rec], cancelled: false, freeBefore: 10, freeAfter: 10)
        let cleanup = ReportBuilder.cleanupResults(del)
        #expect(cleanup[0].rows[0][1] == DeletionStatus.failed.title && cleanup[0].note?.contains("Trash") == true)
    }
}

struct AutoReviewer: WorkflowReviewer {
    var approve: Bool
    func review(_ plan: CleanupPlan) async -> (plan: CleanupPlan, authorization: CleanupAuthorization)? {
        approve ? (plan, CleanupAuthorization(confirming: plan, highRiskAcknowledged: false)) : nil
    }
}

@Suite struct WorkflowTests {
    @Test func validationForbidsRemovalWithoutReview() {
        #expect(throws: WorkflowError.removalWithoutReview) { try Workflow(name: "bad", steps: [.collectCaches, .moveToTrash]).validate() }
        #expect(throws: WorkflowError.removalWithoutReview) { try Workflow(name: "bad", steps: [.collectCaches, .review, .collectDeveloperData, .moveToTrash]).validate() }
        #expect(throws: WorkflowError.removalWithoutReview) { try Workflow(name: "bad", steps: [.collectCaches, .review, .moveToTrash, .moveToTrash]).validate() }
        #expect(throws: WorkflowError.duplicatesWithoutScan) { try Workflow(name: "bad", steps: [.findDuplicates(minimumSizeMB: 1)]).validate() }
        #expect(throws: WorkflowError.empty) { try Workflow(name: "bad", steps: []).validate() }
        for w in Workflow.builtIns { #expect(throws: Never.self) { try w.validate() } }
    }

    @Test func duplicateWorkflowKeepsOneCopyAndStopsWhenReviewIsDeclined() async throws {
        let s = Sandbox()
        s.file("home/Downloads/a.bin", size: 2_000_000, seed: 1); s.file("home/Downloads/a (1).bin", size: 2_000_000, seed: 1)
        s.file("home/Downloads/a (2).bin", size: 2_000_000, seed: 1); s.file("home/Downloads/b.bin", size: 2_000_000, seed: 2)
        let w = Workflow(name: "dups", steps: [.scanFolder(path: s.path("home/Downloads")), .findDuplicates(minimumSizeMB: 1), .review, .moveToTrash, .report])
        let declined = try await WorkflowRunner(policy: SafetyPolicy(home: s.path("home")), trasher: FakeTrasher(bin: s.dir("bin")), home: s.path("home"))
            .run(w, reviewer: AutoReviewer(approve: false))
        #expect(declined.cancelled && declined.report == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.path("home/Downloads")).count == 4)
        let done = try await WorkflowRunner(policy: SafetyPolicy(home: s.path("home")), trasher: FakeTrasher(bin: s.dir("bin")), home: s.path("home"))
            .run(w, reviewer: AutoReviewer(approve: true))
        #expect(done.report?.count(.movedToTrash) == 2 && done.wantsReport && !done.cancelled)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: s.path("home/Downloads"))) == ["a (1).bin", "b.bin"])
        #expect(done.events.count == 5)
    }
}
