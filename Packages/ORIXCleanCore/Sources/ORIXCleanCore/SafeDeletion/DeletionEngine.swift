// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/SafeDeletion/DeletionEngine.swift
// Description: Executes an authorized cleanup: revalidates each item, moves it to the Trash, records every outcome.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Darwin
import Foundation

public enum DeletionMode: String, Sendable, Codable {
    /// Move to the Trash of the item's volume. Space is reclaimed only when the Trash is emptied.
    case moveToTrash
    /// Remove immediately. Not recoverable. Used only for emptying the Trash.
    case permanent
}

public enum DeletionStatus: String, Sendable, Codable, CaseIterable {
    case movedToTrash, permanentlyDeleted, skipped, failed, requiresManualAction

    public var title: String {
        switch self {
        case .movedToTrash: return L("Moved to Trash")
        case .permanentlyDeleted: return L("Permanently deleted")
        case .skipped: return L("Skipped")
        case .failed: return L("Failed")
        case .requiresManualAction: return L("Requires manual action")
        }
    }
}

public struct DeletionRecord: Sendable, Codable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var status: DeletionStatus
    public var detail: String
    /// Where the item now is, when it was moved to the Trash.
    public var trashPath: String?
    public var logicalSize: Int64
    public var allocatedSize: Int64
    public var category: CleanupCategory
    public var restored = false
}

public struct DeletionReport: Sendable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var started: Date
    public var finished: Date
    public var mode: DeletionMode
    public var records: [DeletionRecord]
    public var cancelled: Bool
    /// Free space of the affected volume before and after, as reported by the system.
    public var freeBefore: Int64?
    public var freeAfter: Int64?

    public func count(_ s: DeletionStatus) -> Int { records.filter { $0.status == s }.count }
    public func allocated(_ s: DeletionStatus) -> Int64 { records.filter { $0.status == s }.reduce(0) { $0 + $1.allocatedSize } }
    public var restorable: [DeletionRecord] { records.filter { $0.status == .movedToTrash && !$0.restored && $0.trashPath != nil } }
}

/// Moves one item to the Trash. A protocol so tests can simulate failures.
public protocol Trasher: Sendable {
    func trash(_ url: URL) throws -> URL?
    func remove(_ url: URL) throws
}

public struct SystemTrasher: Trasher {
    public init() {}
    public func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    public func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
}

public final class DeletionEngine: @unchecked Sendable {
    public let policy: SafetyPolicy
    private let trasher: Trasher
    private let lock = NSLock()
    private var cancelledFlag = false
    private var done = 0

    public init(policy: SafetyPolicy = SafetyPolicy(), trasher: Trasher = SystemTrasher()) {
        self.policy = policy
        self.trasher = trasher
    }

    public func cancel() { lock.lock(); cancelledFlag = true; lock.unlock() }
    public var completed: Int { lock.lock(); defer { lock.unlock() }; return done }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledFlag }

    /// Blocking. Every item ends with exactly one record. Items not covered by `authorization` are skipped, never removed.
    public func execute(plan: CleanupPlan, authorization: CleanupAuthorization, mode: DeletionMode = .moveToTrash,
                        runningBundleIDs: Set<String> = []) -> DeletionReport {
        let started = Date()
        let volumePath = plan.items.first?.path
        let freeBefore = volumePath.flatMap { Volumes.containing(($0 as NSString).deletingLastPathComponent)?.available }
        var records: [DeletionRecord] = []
        let targets = Set(plan.items.map(\.path))
        for item in plan.items {
            func record(_ status: DeletionStatus, _ detail: String, trash: String? = nil) {
                records.append(DeletionRecord(path: item.path, status: status, detail: detail, trashPath: trash,
                                              logicalSize: item.measurement.logical, allocatedSize: item.measurement.allocated, category: item.category))
                lock.lock(); done += 1; lock.unlock()
            }
            if isCancelled { record(.skipped, L("Cancelled before this item.")); continue }
            guard authorization.confirmedPaths.contains(item.path) else { record(.skipped, L("Not part of the confirmed selection.")); continue }
            if item.risk == .high, !authorization.highRiskAcknowledged { record(.skipped, L("High-risk item not explicitly acknowledged.")); continue }
            if case let .denied(why) = policy.evaluate(item.path) { record(.skipped, L("Protected: %@", why)); continue }
            if mode == .permanent, item.category != .trash { record(.skipped, L("Permanent deletion is reserved for items already in the Trash.")); continue }

            var st = stat()
            guard lstat(item.path, &st) == 0 else { record(.skipped, L("Already gone.")); continue }
            if item.measurement.fileID != 0, UInt64(st.st_ino) != item.measurement.fileID {
                record(.skipped, L("Replaced by a different item since the scan.")); continue
            }
            let isDirectory = (st.st_mode & S_IFMT) == S_IFDIR
            if !isDirectory, !item.measurement.isDirectory, Int64(st.st_size) != item.measurement.logical {
                record(.skipped, L("Changed since the scan (size differs).")); continue
            }
            let busy = item.closeFirst.filter { runningBundleIDs.contains($0) }
            if !busy.isEmpty { record(.requiresManualAction, L("Quit %@ first, then try again.", busy.joined(separator: ", "))); continue }
            if let original = item.verifyAgainst {
                if targets.contains(original) { record(.skipped, L("The copy to keep is also selected; nothing would remain.")); continue }
                var so = stat()
                guard lstat(original, &so) == 0 else { record(.skipped, L("The copy to keep no longer exists.")); continue }
                if so.st_dev == st.st_dev, so.st_ino == st.st_ino { record(.skipped, L("Same file under another name (hard link); removing it frees nothing.")); continue }
                guard DuplicateFinder.identicalContents(item.path, original) else { record(.skipped, L("No longer identical to the copy to keep.")); continue }
            }
            let url = URL(fileURLWithPath: item.path)
            do {
                switch mode {
                case .moveToTrash:
                    let result = try trasher.trash(url)
                    record(.movedToTrash, result == nil ? L("Moved to the Trash; its new location was not reported.") : L("In the Trash until it is emptied."), trash: result?.path)
                case .permanent:
                    try trasher.remove(url)
                    record(.permanentlyDeleted, L("Removed. This cannot be undone."))
                }
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain, error.code == NSFeatureUnsupportedError {
                    record(.requiresManualAction, L("This volume has no Trash. Remove the item in Finder if you accept permanent deletion."))
                } else if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteVolumeReadOnlyError
                            || (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EROFS) {
                    record(.failed, L("The volume is read-only."))
                } else if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteNoPermissionError || error.code == NSFileReadNoPermissionError {
                    record(.failed, L("Permission denied by macOS."))
                } else {
                    record(.failed, error.localizedDescription)
                }
            }
        }
        let freeAfter = volumePath.flatMap { Volumes.containing(($0 as NSString).deletingLastPathComponent)?.available }
        return DeletionReport(id: UUID(), started: started, finished: Date(), mode: mode, records: records, cancelled: isCancelled,
                              freeBefore: freeBefore, freeAfter: freeAfter)
    }

    public enum RestoreOutcome: Sendable, Equatable {
        case restored
        case notInTrash
        case destinationOccupied
        case failed(String)
    }

    /// Puts an item moved to the Trash back where it was. Works only while it is still in the Trash and the place is free.
    public func restore(_ record: DeletionRecord) -> RestoreOutcome {
        guard record.status == .movedToTrash, let trashPath = record.trashPath else { return .notInTrash }
        let fm = FileManager.default
        guard fm.fileExists(atPath: trashPath) else { return .notInTrash }
        var st = stat()
        if lstat(record.path, &st) == 0 { return .destinationOccupied }
        do {
            try fm.createDirectory(atPath: (record.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try fm.moveItem(atPath: trashPath, toPath: record.path)
            return .restored
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
