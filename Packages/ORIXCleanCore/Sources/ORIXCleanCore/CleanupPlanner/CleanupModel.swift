// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/CleanupPlanner/CleanupModel.swift
// Description: Cleanup candidates, risk levels and the plan shown in the cleanup preview.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation

public enum Risk: Int, Sendable, Codable, Comparable, CaseIterable {
    /// Recreatable data with a documented, verified location.
    case low = 0
    /// May hold something the user wants; look before removing.
    case review = 1
    /// Potentially important application or system data.
    case high = 2

    public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
    public var title: String {
        switch self {
        case .low: return L("Low risk")
        case .review: return L("Review required")
        case .high: return L("High risk")
        }
    }
}

public enum CleanupCategory: String, Sendable, Codable, CaseIterable {
    case appCache, browserCache, logs, temporary, developer, download, archive, duplicate, similarImage, largeFile,
         application, appSupportFile, leftover, trash, other

    public var title: String {
        switch self {
        case .appCache: return L("Application caches")
        case .browserCache: return L("Browser caches")
        case .logs: return L("Logs")
        case .temporary: return L("Temporary files")
        case .developer: return L("Developer data")
        case .download: return L("Downloads")
        case .archive: return L("Archives and disk images")
        case .duplicate: return L("Duplicates")
        case .similarImage: return L("Similar images")
        case .largeFile: return L("Large files")
        case .application: return L("Applications")
        case .appSupportFile: return L("Application files")
        case .leftover: return L("Leftover files")
        case .trash: return L("Trash")
        case .other: return L("Other")
        }
    }
}

/// One item proposed for removal. Nothing is removed until it passes through a `CleanupAuthorization`.
public struct CleanupItem: Identifiable, Hashable, Sendable, Codable {
    public var id: String { path }
    public var path: String
    public var category: CleanupCategory
    public var risk: Risk
    /// Why this item is a candidate.
    public var reason: String
    /// What happens after it is removed.
    public var consequence: String
    public var measurement: Measurement
    /// Tool or application that owns the item, when known.
    public var owner: String?
    /// What it costs to get the data back (rebuild, download…).
    public var regeneration: String?
    /// Bundle identifiers that should not be running while the item is removed.
    public var closeFirst: [String]
    /// For a duplicate: the copy that stays. The engine compares both byte for byte before removing.
    public var verifyAgainst: String?
    /// How sure the association with `owner` is, when it was inferred.
    public var confidenceNote: String?

    public init(path: String, category: CleanupCategory, risk: Risk, reason: String, consequence: String, measurement: Measurement,
                owner: String? = nil, regeneration: String? = nil, closeFirst: [String] = [], verifyAgainst: String? = nil,
                confidenceNote: String? = nil) {
        self.path = path
        self.category = category
        self.risk = risk
        self.reason = reason
        self.consequence = consequence
        self.measurement = measurement
        self.owner = owner
        self.regeneration = regeneration
        self.closeFirst = closeFirst
        self.verifyAgainst = verifyAgainst
        self.confidenceNote = confidenceNote
    }

    public var name: String { (path as NSString).lastPathComponent }
}

/// The set of items shown in the cleanup preview, with totals computed from their measurements.
public struct CleanupPlan: Sendable {
    public var items: [CleanupItem]
    public init(items: [CleanupItem]) {
        // A path listed twice, or inside another listed directory, is kept once.
        var seen = Set<String>()
        let sorted = items.sorted { $0.path.count < $1.path.count }
        var kept: [CleanupItem] = []
        for item in sorted {
            if seen.contains(item.path) { continue }
            if kept.contains(where: { $0.measurement.isDirectory && item.path.hasPrefix($0.path + "/") }) { continue }
            seen.insert(item.path)
            kept.append(item)
        }
        self.items = kept.sorted { $0.measurement.allocated > $1.measurement.allocated }
    }

    public var logicalSize: Int64 { items.reduce(0) { $0 + $1.measurement.logical } }
    public var allocatedSize: Int64 { items.reduce(0) { $0 + $1.measurement.allocated } }
    public var fileCount: Int { items.reduce(0) { $0 + $1.measurement.files } }
    public var recoverable: RecoverableEstimate { items.reduce(.zero) { $0 + $1.measurement.recoverable } }
    public var highestRisk: Risk { items.map(\.risk).max() ?? .low }
    public var byRisk: [(Risk, [CleanupItem])] { Risk.allCases.reversed().compactMap { r in
        let list = items.filter { $0.risk == r }
        return list.isEmpty ? nil : (r, list)
    } }
    public var appsToClose: [String] { Array(Set(items.flatMap(\.closeFirst))).sorted() }
}

/// Explicit consent of the user for a precise list of paths. The deletion engine refuses anything not listed here.
public struct CleanupAuthorization: Sendable {
    public let confirmedPaths: Set<String>
    public let highRiskAcknowledged: Bool
    public let confirmedAt: Date

    /// Create only from a user confirmation in the cleanup preview.
    public init(confirming plan: CleanupPlan, highRiskAcknowledged: Bool) {
        confirmedPaths = Set(plan.items.map(\.path))
        self.highRiskAcknowledged = highRiskAcknowledged
        confirmedAt = Date()
    }
}
