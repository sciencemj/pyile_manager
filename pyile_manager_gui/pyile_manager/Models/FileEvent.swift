//
//  FileEvent.swift
//  pyile_manager
//
//  File event models for monitoring, persistent history, and undo
//

import Foundation

struct FileEvent: Identifiable, Codable {
    var schemaVersion: Int = 1
    let id: UUID
    let type: String  // "file_moved", "file_renamed", "duplicate_trashed", "undo"
    let timestamp: Double

    /// Links the move and rename of one physical file so they undo as a unit.
    let groupID: UUID?

    // For file_moved and duplicate_trashed events
    let filename: String?
    let from: String?
    let to: String?
    let destination: String?

    // For file_renamed events
    let oldName: String?
    let newName: String?
    let path: String?
    let fullPath: String?

    // For duplicate_trashed events: the exact URL trashItem reported
    let trashURL: String?

    // For undo records: the id of the event that was undone
    let ref: UUID?

    init(type: String, timestamp: Double, groupID: UUID? = nil,
         filename: String? = nil, from: String? = nil, to: String? = nil, destination: String? = nil,
         oldName: String? = nil, newName: String? = nil, path: String? = nil, fullPath: String? = nil,
         trashURL: String? = nil, ref: UUID? = nil) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.groupID = groupID
        self.filename = filename
        self.from = from
        self.to = to
        self.destination = destination
        self.oldName = oldName
        self.newName = newName
        self.path = path
        self.fullPath = fullPath
        self.trashURL = trashURL
        self.ref = ref
    }

    // Human-readable description
    var displayText: String {
        switch type {
        case "file_moved":
            return "\(filename ?? "File") → \(destination ?? "Unknown")"
        case "file_renamed":
            return "\(oldName ?? "File") → \(newName ?? "Unknown")"
        case "duplicate_trashed":
            return "\(filename ?? "File") → Trash (duplicate)"
        default:
            return "Unknown event"
        }
    }

    var displayIcon: String {
        switch type {
        case "file_moved":
            return "arrow.right.square"
        case "file_renamed":
            return "pencil.circle"
        case "duplicate_trashed":
            return "trash.circle"
        default:
            return "questionmark.circle"
        }
    }
}

/// A history event plus its computed undone-state (folded from "undo" records).
struct HistoryEntry: Identifiable {
    let event: FileEvent
    var undone: Bool
    var id: UUID { event.id }
}
