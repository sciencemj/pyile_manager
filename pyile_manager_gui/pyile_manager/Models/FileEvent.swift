//
//  FileEvent.swift
//  pyile_manager
//
//  File event models for monitoring notifications
//

import Foundation

struct FileEvent: Identifiable {
    let id = UUID()
    let type: String  // "file_moved" or "file_renamed"
    let timestamp: Double

    // For file_moved events
    let filename: String?
    let from: String?
    let to: String?
    let destination: String?

    // For file_renamed events
    let oldName: String?
    let newName: String?
    let path: String?
    let fullPath: String?

    // Convenience init for file_moved
    init(type: String, timestamp: Double,
         filename: String? = nil, from: String? = nil, to: String? = nil, destination: String? = nil,
         oldName: String? = nil, newName: String? = nil, path: String? = nil, fullPath: String? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.filename = filename
        self.from = from
        self.to = to
        self.destination = destination
        self.oldName = oldName
        self.newName = newName
        self.path = path
        self.fullPath = fullPath
    }

    // Human-readable description
    var displayText: String {
        switch type {
        case "file_moved":
            return "\(filename ?? "File") → \(destination ?? "Unknown")"
        case "file_renamed":
            return "\(oldName ?? "File") → \(newName ?? "Unknown")"
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
        default:
            return "questionmark.circle"
        }
    }
}
