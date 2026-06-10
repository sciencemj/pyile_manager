//
//  UndoCoordinator.swift
//  pyile_manager
//
//  Reverses recorded file events. Safety invariants:
//  - never overwrites an occupied restore target
//  - never creates a missing original directory
//  - move+rename chains (shared groupID) undo as a unit, newest first
//

import Foundation

enum UndoError: LocalizedError {
    case fileNoLongerExists(String)
    case originalLocationMissing(String)
    case targetOccupied(String)
    case unsupportedEventType(String)
    case partial(undone: [UUID], cause: Error)

    var errorDescription: String? {
        switch self {
        case .fileNoLongerExists(let path):
            return "Cannot undo: the file is no longer at \(path)."
        case .originalLocationMissing(let dir):
            return "Cannot undo: the original folder \(dir) no longer exists."
        case .targetOccupied(let path):
            return "Cannot undo: another file now exists at \(path)."
        case .unsupportedEventType(let type):
            return "Cannot undo event of type \(type)."
        case .partial(let undone, let cause):
            return "Undo incomplete: \(undone.count) linked action(s) were undone before a step failed. \(cause.localizedDescription)"
        }
    }
}

struct UndoCoordinator {

    /// Undo an entry. If the entry belongs to a group (move+rename of one file),
    /// the whole not-yet-undone group is reversed, newest first.
    /// Returns the ids of all events that were undone.
    /// On a mid-chain failure, throws `UndoError.partial` carrying the ids that
    /// DID succeed on disk — the caller must mark those undone so a retry can
    /// resume with just the remaining events.
    static func undo(_ entry: HistoryEntry, in history: [HistoryEntry]) throws -> [UUID] {
        let chain = chainFor(entry, in: history)
        var undone: [UUID] = []
        for item in chain {
            do {
                try undoSingle(item.event)
            } catch {
                throw UndoError.partial(undone: undone, cause: error)
            }
            undone.append(item.event.id)
        }
        return undone
    }

    /// All not-yet-undone events sharing the entry's groupID, newest first.
    static func chainFor(_ entry: HistoryEntry, in history: [HistoryEntry]) -> [HistoryEntry] {
        guard let groupID = entry.event.groupID else { return [entry] }
        let chain = history
            .filter { $0.event.groupID == groupID && !$0.undone && $0.event.type != "undo" }
            .sorted { $0.event.timestamp > $1.event.timestamp }
        return chain.isEmpty ? [entry] : chain
    }

    // MARK: - Private

    private static func undoSingle(_ event: FileEvent) throws {
        switch event.type {
        case "file_moved":
            guard let from = event.from, let to = event.to else {
                throw UndoError.unsupportedEventType(event.type)
            }
            try moveBack(current: to, original: from)

        case "file_renamed":
            guard let dir = event.path, let oldName = event.oldName, let fullPath = event.fullPath else {
                throw UndoError.unsupportedEventType(event.type)
            }
            let original = (dir as NSString).appendingPathComponent(oldName)
            try moveBack(current: fullPath, original: original)

        case "duplicate_trashed":
            guard let trashPath = event.trashURL, let original = event.from else {
                throw UndoError.unsupportedEventType(event.type)
            }
            try moveBack(current: trashPath, original: original)

        default:
            throw UndoError.unsupportedEventType(event.type)
        }
    }

    private static func moveBack(current: String, original: String) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: current) else {
            throw UndoError.fileNoLongerExists(current)
        }

        let originalDir = (original as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: originalDir, isDirectory: &isDir), isDir.boolValue else {
            // Never auto-create: it could land on the wrong volume or
            // resurrect a path the user deleted on purpose.
            throw UndoError.originalLocationMissing(originalDir)
        }

        guard !fm.fileExists(atPath: original) else {
            throw UndoError.targetOccupied(original)
        }

        try fm.moveItem(atPath: current, toPath: original)
    }
}
