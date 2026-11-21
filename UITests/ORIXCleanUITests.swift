// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : UITests/ORIXCleanUITests.swift
// Description      : End-to-end UI tests on a disposable sample home folder
//                    stored on a test disk image (Scripts/build.sh uitest).
//                    Cleanup tests really move files to the Trash of that disk
//                    image; nothing outside it is touched.
// Module           : UITests
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

import XCTest

final class ORIXCleanUITests: XCTestCase {
    static let home = "/tmp/orix-uitest/home"
    static let exports = "/tmp/orix-uitest-exports-" + UUID().uuidString.prefix(8)
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.home + "/Movies"), "Sample home missing: run Scripts/build.sh uitest")
    }

    override func tearDown() { app?.terminate() }

    @discardableResult
    func launch(section: String = "overview", scan: Bool = true, analyze: Bool = false, extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-ORIXHome", Self.home, "-ORIXStore", "memory", "-ORIXSection", section, "-ORIXExportDir", Self.exports,
                               "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        if !extra.contains("-ORIXOnboarding") { app.launchArguments += ["-ORIXSkipOnboarding", "YES"] }
        if scan { app.launchArguments += ["-ORIXScanRoot", Self.home] }
        if analyze { app.launchArguments += ["-ORIXAutoAnalyze", "YES"] }
        app.launchArguments += extra.filter { $0 != "-ORIXOnboarding" }
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func text(containing s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@ OR title CONTAINS %@", s, s, s)).firstMatch
    }

    /// Shows another section by relaunching on it (independent of sidebar scroll position).
    func go(_ section: String, scan: Bool = true, analyze: Bool = false) {
        app.terminate()
        launch(section: section, scan: scan, analyze: analyze)
    }
    /// Clicks with the app brought back to the front first; other automation on this Mac can take focus mid-test.
    func tap(_ e: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0 ..< 4 {
            app.activate()
            if e.waitForExistence(timeout: 5), e.isHittable { e.click(); return }
            Thread.sleep(forTimeInterval: 0.5 + Double(attempt) * 0.5)
        }
        app.activate()
        e.click()   // last attempt: let XCTest report its own diagnosis if this fails
    }

    func type(_ string: String, into e: XCUIElement) {
        for _ in 0 ..< 4 {
            tap(e)
            if (e.value(forKey: "hasKeyboardFocus") as? Bool) == true { e.typeText(string); return }
            Thread.sleep(forTimeInterval: 0.7)
        }
        e.typeText(string)
    }

    func attach(_ name: String) {
        let a = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    func testFirstLaunchShowsOnboardingAndNothingIsScanned() {
        launch(scan: false, extra: ["-ORIXOnboarding", "-onboarded", "NO"])
        let start = element("onboarding.start")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Nothing is removed without you").exists)
        attach("onboarding")
        tap(start)
        XCTAssertTrue(element("overview.scanHome").waitForExistence(timeout: 5))
        XCTAssertFalse(element("selection.review").exists)
    }

    func testScanStorageMapSearchAndSidebarNavigation() {
        launch(section: "map")
        XCTAssertTrue(element("map.canvas").waitForExistence(timeout: 20))
        XCTAssertTrue(element("map.list").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Library").waitForExistence(timeout: 5))
        attach("storage-map")
        let search = element("map.search")
        type("Conference", into: search)
        XCTAssertTrue(text(containing: "Conference talk").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "matches").exists)
        go("largeFiles")
        XCTAssertTrue(element("large.list").waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Lisbon trip 4K.mov").waitForExistence(timeout: 5))
        attach("large-files")
    }

    func testDuplicatesAndSimilarImages() {
        launch(section: "duplicates", analyze: true)
        XCTAssertTrue(element("duplicates.list").waitForExistence(timeout: 40))
        XCTAssertTrue(text(containing: "3 copies").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "shares storage").exists)
        attach("duplicates")
        go("similar", analyze: true)
        XCTAssertTrue(element("similar.list").waitForExistence(timeout: 40))
        XCTAssertTrue(text(containing: "similar images").exists)
        attach("similar-images")
    }

    func testCachesDeveloperDownloadsAndTrashLists() {
        launch(section: "caches", scan: false)
        XCTAssertTrue(element("caches.list").waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "Google Chrome").waitForExistence(timeout: 5))
        XCTAssertFalse(element("selection.review").exists, "nothing may be preselected")
        go("developer", scan: false)
        XCTAssertTrue(element("developer.list").waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "Atlas-bqxmfldzjgheuz").waitForExistence(timeout: 5))
        go("downloads", scan: false)
        XCTAssertTrue(element("downloads.list").waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "Sketcher-4.2.dmg").waitForExistence(timeout: 5))
        go("trash", scan: false)
        XCTAssertTrue(element("trash.list").waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "Old presentation.key").waitForExistence(timeout: 5))
    }

    func testUninstallPreviewCancelThenRealCleanupAndPutBack() {
        let appPath = Self.home + "/Applications/Notably.app"
        XCTAssertTrue(FileManager.default.fileExists(atPath: appPath))
        launch(section: "applications", scan: false)
        XCTAssertTrue(element("apps.list").waitForExistence(timeout: 20))
        tap(text(containing: "Notably"))
        let select = element("apps.selectUninstall")
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "isEnabled == true")
        wait(for: [expectation(for: enabled, evaluatedWith: select)], timeout: 15)
        tap(select)
        if !element("selection.review").waitForExistence(timeout: 5) { print("HIERARCHY\n" + app.debugDescription) }
        XCTAssertTrue(element("selection.review").exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appPath), "selecting must not remove anything")
        tap(element("selection.review"))
        XCTAssertTrue(element("preview.list").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Applications/Notably.app").exists)
        attach("cleanup-preview")
        tap(element("preview.cancel"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appPath), "cancelling the preview must not remove anything")
        tap(element("selection.review"))
        XCTAssertTrue(element("preview.confirm").waitForExistence(timeout: 5))
        tap(element("preview.confirm"))
        XCTAssertTrue(element("results.list").waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "Moved to Trash").exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appPath), "the confirmed item must be gone from its location")
        attach("cleanup-results")
        tap(app.buttons["Put Back"].firstMatch)
        XCTAssertTrue(text(containing: "Put back").waitForExistence(timeout: 5))
        tap(element("results.done"))
        XCTAssertFalse(element("selection.review").exists)
    }

    func testReportExportWritesAFile() throws {
        launch(section: "reports")
        XCTAssertTrue(element("reports.preview").waitForExistence(timeout: 20))
        tap(element("reports.export"))
        let found = NSPredicate { _, _ in ((try? FileManager.default.contentsOfDirectory(atPath: Self.exports)) ?? []).contains { $0.hasSuffix(".pdf") } }
        wait(for: [expectation(for: found, evaluatedWith: nil)], timeout: 10)
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: Self.exports).first { $0.hasSuffix(".pdf") })
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.exports + "/" + file))
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
        attach("reports")
    }

    func testActionStopsWhenTheReviewIsDeclined() {
        let cache = Self.home + "/Library/Caches/io.renderly.app"
        launch(section: "actions", scan: false)
        let run = element("actions.run.builtin.caches")
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        tap(run)
        XCTAssertTrue(element("preview.list").waitForExistence(timeout: 30))
        tap(element("preview.cancel"))
        XCTAssertTrue(text(containing: "Nothing was removed").waitForExistence(timeout: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache))
    }

    func testSettingsLightModeHistoryAndWindowResize() {
        launch(section: "history", extra: ["-ORIXAppearance", "light"])
        XCTAssertTrue(text(containing: "Cleanup history").waitForExistence(timeout: 10))
        attach("history-light")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(text(containing: "Storage map colours").waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        // Layout at the minimum size and at a large size (the window is really resized by the app at launch).
        for (size, minWidth) in [("980x620", 970.0), ("1800x1100", 1500.0)] {
            app.terminate()
            launch(section: "map", extra: ["-ORIXWindowSize", size])
            XCTAssertTrue(element("map.canvas").waitForExistence(timeout: 20))
            let frame = app.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(Double(frame.width), minWidth)
            if size == "980x620" { XCTAssertLessThanOrEqual(Double(frame.width), 1000) }
            XCTAssertTrue(element("map.search").exists)
            XCTAssertTrue(element("toolbar.scanFolder").exists)
            attach("map-" + size)
        }
    }
}
