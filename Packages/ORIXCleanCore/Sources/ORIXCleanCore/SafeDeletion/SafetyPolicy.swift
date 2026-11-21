// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Packages/ORIXCleanCore/Sources/ORIXCleanCore/SafeDeletion/SafetyPolicy.swift
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

// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/SafeDeletion/SafetyPolicy.swift
// Description: Last line of defence: paths the deletion engine never touches, whatever asked for it.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation

public struct SafetyPolicy: Sendable {
    public enum Verdict: Sendable, Equatable {
        case allowed
        case denied(String)
    }

    public let home: String
    public init(home: String = NSHomeDirectory()) { self.home = Self.normalize(home) }

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        for (alias, real) in [("/tmp", "/private/tmp"), ("/var", "/private/var"), ("/etc", "/private/etc")] where p == alias || p.hasPrefix(alias + "/") {
            p = real + p.dropFirst(alias.count)
        }
        if p.hasPrefix("/System/Volumes/Data/") { p = String(p.dropFirst("/System/Volumes/Data".count)) }
        return p
    }

    static let librariesWithPrivateStructure: Set<String> = ["photoslibrary", "musiclibrary", "tvlibrary", "aplibrary", "imovielibrary",
                                                            "fcpbundle", "logicx", "sparsebundle", "pvm", "vmwarevm", "utm"]

    public func evaluate(_ rawPath: String) -> Verdict {
        guard rawPath.hasPrefix("/") else { return .denied(L("Not an absolute path.")) }
        if rawPath.split(separator: "/").contains("..") { return .denied(L("The path contains a parent reference.")) }
        let path = Self.normalize(rawPath)
        let parts = path.split(separator: "/").map(String.init)
        if parts.isEmpty { return .denied(L("The root of the startup volume is protected.")) }

        let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db", "/private/var/root", "/Library/Apple",
                              "/cores", "/dev", "/opt", "/Library/Developer/CommandLineTools", home + "/Library/Keychains"]
        for prefix in systemPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return .denied(L("Part of macOS or of a system-managed area."))
        }
        if path.hasPrefix("/private/var"), !path.hasPrefix("/private/var/folders/"), !(path.hasPrefix("/private/var/tmp/")) {
            return .denied(L("Part of macOS or of a system-managed area."))
        }
        if path == "/private" || path == "/private/tmp" || path == "/private/var/tmp" { return .denied(L("A system folder itself is never removed.")) }

        let exact: Set<String> = ["/Applications", "/Applications/Utilities", "/Library", "/Users", "/Users/Shared", "/Volumes", home,
                                  home + "/Library", home + "/Applications"]
        if exact.contains(path) { return .denied(L("A top-level folder itself is never removed.")) }
        // Direct children of /Library, ~/Library and the home folder are structural.
        for base in ["/Library", home + "/Library", home, "/Users"] where (path as NSString).deletingLastPathComponent == base {
            if base == home, parts.last?.hasPrefix(".") == true, parts.last != ".Trash" { continue }
            if base == home, !Self.standardHomeFolders.contains(parts.last ?? "") { continue }
            return .denied(L("A standard folder itself is never removed; choose items inside it."))
        }
        if parts.count == 2, parts[0] == "Volumes" { return .denied(L("The root of a volume is protected.")) }
        // A Trash folder itself (per-user Trash of a volume) is structural; only its content can be removed.
        if parts.count == 4, parts[0] == "Volumes", parts[2] == ".Trashes" { return .denied(L("A volume service folder is protected.")) }
        // The per-user temporary and cache roots themselves.
        if path.hasPrefix("/private/var/folders/"), parts.count <= 6 { return .denied(L("A system folder itself is never removed.")) }
        // Credentials and keys kept in dot-folders of the home folder.
        for secret in [".ssh", ".gnupg", ".aws", ".kube", ".config/gcloud", ".password-store"] where path == home + "/" + secret || path.hasPrefix(home + "/" + secret + "/") {
            return .denied(L("Holds keys or credentials; ORIX Clean never removes it."))
        }
        if parts.count >= 3, parts[0] == "Volumes", parts[2] == ".Trashes" || parts[2] == ".Spotlight-V100" || parts[2] == ".fseventsd", parts.count == 3 {
            return .denied(L("A volume service folder is protected."))
        }
        // Never reach inside an application or a library package: remove the whole item or nothing.
        for (i, part) in parts.dropLast().enumerated() {
            let ext = (part as NSString).pathExtension.lowercased()
            if ext == "app" { return .denied(L("Inside an application bundle. Remove the whole application instead.")) }
            if Self.librariesWithPrivateStructure.contains(ext) {
                return .denied(L("Inside a library package (%@). Use the application that owns it.", parts[i]))
            }
        }
        return .allowed
    }

    static let standardHomeFolders: Set<String> = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Library",
                                                  "Applications", ".Trash"]
}
