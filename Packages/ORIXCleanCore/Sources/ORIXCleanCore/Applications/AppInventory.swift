// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Packages/ORIXCleanCore/Sources/ORIXCleanCore/Applications/AppInventory.swift
// Module           : ORIXCleanCore
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

// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/Applications/AppInventory.swift
// Description: Installed application discovery, code-signature facts, associated files and leftover detection.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation
import Security

public struct SignatureInfo: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable { case apple, appStore, developerID, adHoc, unsigned, other }
    public var kind: Kind
    public var teamID: String?
    /// Leaf certificate common name, e.g. "Developer ID Application: Name (TEAM)".
    public var authority: String?
    public var valid: Bool
}

public struct InstalledApp: Sendable, Hashable, Identifiable, Codable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var bundleID: String
    public var version: String
    public var build: String
    /// Under /System or shipped as part of macOS: never offered for removal.
    public var isSystem: Bool
    public var signature: SignatureInfo?
    public var measurement: Measurement?
    /// Last use recorded by Spotlight, when available.
    public var lastUsed: Date?
}

public struct AssociatedFile: Sendable, Hashable, Identifiable, Codable {
    public enum Confidence: Int, Sendable, Codable, Comparable {
        /// Named only after the application; another product could use the same name.
        case nameMatch = 0
        /// Shared container keyed by the developer team; other apps of the same developer may use it.
        case sharedGroup = 1
        /// Named exactly after the bundle identifier.
        case identifier = 2
        public static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }
        public var title: String {
            switch self {
            case .identifier: return L("Matches the bundle identifier")
            case .sharedGroup: return L("Shared by the developer's apps")
            case .nameMatch: return L("Name match only")
            }
        }
    }
    public var id: String { path }
    public var path: String
    public var location: String
    public var confidence: Confidence
    public var measurement: Measurement
}

public enum AppInventory {
    public static let defaultDirectories = ["/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications", "/System/Applications",
                                            "/System/Applications/Utilities"]

    /// Reads the bundles found in the given folders. Sizes are measured separately (`measure`).
    public static func discover(directories: [String] = defaultDirectories) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for dir in directories {
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() where name.hasSuffix(".app") {
                let path = dir + "/" + name
                guard seen.insert(path).inserted, let app = read(path) else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func read(_ path: String) -> InstalledApp? {
        guard let bundle = Bundle(path: path), let info = bundle.infoDictionary, let id = bundle.bundleIdentifier else { return nil }
        let display = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let system = path.hasPrefix("/System/") || path.hasPrefix("/Library/Apple/")
        return InstalledApp(path: path, name: display, bundleID: id, version: info["CFBundleShortVersionString"] as? String ?? "",
                            build: info["CFBundleVersion"] as? String ?? "", isSystem: system, signature: nil, measurement: nil, lastUsed: nil)
    }

    /// Static code-signature facts. Does not execute the application.
    public static func signature(of path: String) -> SignatureInfo {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else {
            return SignatureInfo(kind: .unsigned, teamID: nil, authority: nil, valid: false)
        }
        var cfInfo: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &cfInfo) == errSecSuccess,
              let info = cfInfo as? [String: Any] else {
            return SignatureInfo(kind: .unsigned, teamID: nil, authority: nil, valid: false)
        }
        let valid = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), nil) == errSecSuccess
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        var authority: String?
        if let leaf = certs.first {
            var cn: CFString?
            SecCertificateCopyCommonName(leaf, &cn)
            authority = cn as String?
        }
        var kind: SignatureInfo.Kind = .other
        if info[kSecCodeInfoIdentifier as String] == nil { kind = .unsigned }
        else if certs.isEmpty { kind = .adHoc }
        else if let a = authority {
            if a.hasPrefix("Developer ID Application") { kind = .developerID }
            else if a.hasSuffix("Software Signing") { kind = .apple }
            else if a.hasPrefix("Apple Mac OS Application Signing") || a.hasPrefix("Apple Distribution") || a.hasPrefix("3rd Party Mac Developer") { kind = .appStore }
        }
        return SignatureInfo(kind: kind, teamID: team, authority: authority, valid: valid)
    }

    public static func lastUsed(_ path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Fills size, signature and last-use date. Blocking.
    public static func measure(_ app: InstalledApp) -> InstalledApp {
        var a = app
        a.measurement = Measure.item(app.path)
        a.signature = signature(of: app.path)
        a.lastUsed = lastUsed(app.path)
        return a
    }

    /// Library locations that hold per-application data, with the naming convention used in each.
    static let locations: [(dir: String, suffixes: [String])] = [
        ("Library/Application Support", [""]),
        ("Library/Caches", [""]),
        ("Library/Preferences", [".plist"]),
        ("Library/Preferences/ByHost", [".plist"]),
        ("Library/Containers", [""]),
        ("Library/Application Scripts", [""]),
        ("Library/Saved Application State", [".savedState"]),
        ("Library/HTTPStorages", ["", ".binarycookies"]),
        ("Library/WebKit", [""]),
        ("Library/Logs", [""]),
        ("Library/Cookies", [".binarycookies"]),
        ("Library/LaunchAgents", [".plist"]),
    ]

    /// Files in the user Library that belong, or appear to belong, to an application. Never includes documents.
    public static func associatedFiles(for app: InstalledApp, home: String = NSHomeDirectory()) -> [AssociatedFile] {
        let fm = FileManager.default
        var out: [AssociatedFile] = []
        var seen = Set<String>()
        func add(_ path: String, _ location: String, _ c: AssociatedFile.Confidence) {
            guard seen.insert(path).inserted, let m = Measure.item(path) else { return }
            out.append(AssociatedFile(path: path, location: location, confidence: c, measurement: m))
        }
        let id = app.bundleID
        for loc in locations {
            let dir = home + "/" + loc.dir
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                var stem = name
                for s in loc.suffixes where !s.isEmpty && stem.hasSuffix(s) { stem = String(stem.dropLast(s.count)); break }
                if stem == id || (loc.dir.hasSuffix("ByHost") && stem.hasPrefix(id + ".")) {
                    add(dir + "/" + name, loc.dir, .identifier)
                } else if stem.hasPrefix(id + "."), loc.dir != "Library/Application Support" {
                    // Helper identifiers (com.vendor.app.helper) follow the main identifier.
                    add(dir + "/" + name, loc.dir, .identifier)
                } else if (loc.dir == "Library/Application Support" || loc.dir == "Library/Caches" || loc.dir == "Library/Logs"),
                          name == app.name, app.name.count >= 4 {
                    add(dir + "/" + name, loc.dir, .nameMatch)
                }
            }
        }
        if let team = app.signature?.teamID, !team.isEmpty, let names = try? fm.contentsOfDirectory(atPath: home + "/Library/Group Containers") {
            for name in names where name.hasPrefix(team + ".") { add(home + "/Library/Group Containers/" + name, "Library/Group Containers", .sharedGroup) }
        }
        return out.sorted { $0.measurement.allocated > $1.measurement.allocated }
    }

    /// Cleanup items for an uninstall: the bundle plus the chosen associated files.
    public static func uninstallItems(app: InstalledApp, files: [AssociatedFile]) -> [CleanupItem] {
        guard !app.isSystem else { return [] }
        var items: [CleanupItem] = []
        if let m = app.measurement ?? Measure.item(app.path) {
            items.append(CleanupItem(path: app.path, category: .application, risk: .review,
                                     reason: L("Application bundle of %@ (%@).", app.name, app.bundleID),
                                     consequence: L("The application is no longer installed. Your documents are not touched."),
                                     measurement: m, owner: app.name, regeneration: L("Reinstall from its original source"), closeFirst: [app.bundleID]))
        }
        for f in files {
            let risk: Risk = f.confidence == .identifier ? .review : .high
            items.append(CleanupItem(path: f.path, category: .appSupportFile, risk: risk,
                                     reason: L("Found in %@ for %@.", f.location, app.name),
                                     consequence: L("Settings and local data of the application stored here are lost. A later reinstall starts fresh."),
                                     measurement: f.measurement, owner: app.name, regeneration: L("Not regenerated"), closeFirst: [app.bundleID],
                                     confidenceNote: f.confidence.title))
        }
        return items
    }
}

public struct Leftover: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var identifier: String
    public var location: String
    public var measurement: Measurement

    public var cleanupItem: CleanupItem {
        CleanupItem(path: path, category: .leftover, risk: .review,
                    reason: L("Named after the identifier “%@”, and no installed application with that identifier was found.", identifier),
                    consequence: L("If the application is installed somewhere ORIX Clean did not look, or is a command-line tool, it loses these settings or data."),
                    measurement: measurement, owner: identifier, regeneration: L("Not regenerated"),
                    confidenceNote: L("Inferred from the name only. Not proof that the item is orphaned."))
    }
}

public enum LeftoverFinder {
    static let prefixes = ["com.", "org.", "io.", "net.", "app.", "dev.", "co.", "me.", "ai.", "us.", "de.", "fr.", "ca.", "uk.", "jp.", "se.", "ch.", "at.", "nl.", "it.", "tv.", "ru.", "cn.", "eu.", "info.", "pro.", "xyz.", "tech.", "company."]

    static func looksLikeIdentifier(_ s: String) -> Bool {
        guard prefixes.contains(where: { s.lowercased().hasPrefix($0) }) else { return false }
        return s.split(separator: ".").count >= 3 && !s.contains(" ")
    }

    /// `resolver` answers whether any application with this identifier is registered with the system (Launch Services).
    public static func find(installed: [InstalledApp], home: String = NSHomeDirectory(), minimumSize: Int64 = 16 * 1024,
                            resolver: (String) -> Bool = { _ in false }) -> [Leftover] {
        let ids = installed.map { $0.bundleID.lowercased() }
        func known(_ identifier: String) -> Bool {
            let x = identifier.lowercased()
            if x.hasPrefix("com.apple.") { return true }
            for id in ids where x == id || x.hasPrefix(id + ".") || id.hasPrefix(x + ".") { return true }
            // Same vendor prefix (com.vendor.*) as an installed app: likely a shared component; do not flag.
            let vendor = x.split(separator: ".").prefix(2).joined(separator: ".")
            if ids.contains(where: { $0.hasPrefix(vendor + ".") }) { return true }
            var probe = identifier
            while probe.split(separator: ".").count >= 3 {
                if resolver(probe) { return true }
                probe = probe.split(separator: ".").dropLast().joined(separator: ".")
            }
            return false
        }
        var out: [Leftover] = []
        for loc in AppInventory.locations where loc.dir != "Library/LaunchAgents" && loc.dir != "Library/Preferences/ByHost" {
            let dir = home + "/" + loc.dir
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() {
                var stem = name
                for s in loc.suffixes where !s.isEmpty && stem.hasSuffix(s) { stem = String(stem.dropLast(s.count)); break }
                guard looksLikeIdentifier(stem), !known(stem) else { continue }
                guard let m = Measure.item(dir + "/" + name), m.allocated >= minimumSize else { continue }
                out.append(Leftover(path: dir + "/" + name, identifier: stem, location: loc.dir, measurement: m))
            }
        }
        return out.sorted { $0.measurement.allocated > $1.measurement.allocated }
    }
}
