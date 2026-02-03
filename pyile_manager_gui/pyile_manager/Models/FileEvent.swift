//
//  FileEvent.swift
//  pyile_manager
//
//  WebSocket notification models for file events
//

import Foundation

struct FileEvent: Codable, Identifiable {
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
    
    enum CodingKeys: String, CodingKey {
        case type, timestamp, filename, from, to, destination, path
        case oldName = "old_name"
        case newName = "new_name"
        case fullPath = "full_path"
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
