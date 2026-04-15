//
//  AppConfig.swift
//  pyile_manager
//
//  Data models for application configuration
//

import Foundation

// Settings configuration
struct Settings: Codable {
    var removeDuplicate: Bool
    var renameByAi: Bool
    var renameAi: String
    var ocrAi: String

    enum CodingKeys: String, CodingKey {
        case removeDuplicate = "remove_duplicate"
        case renameByAi = "rename_by_ai"
        case renameAi = "rename_ai"
        case ocrAi = "ocr_ai"
    }
}

// Move configuration (URL and tag mappings)
struct Move: Codable {
    var url: [String: String]
    var tag: [String: String]
}

// Schema configuration
struct Schema: Codable {
    var move: Move
    var rename: [String]
}

// Main application configuration
struct AppConfig: Codable {
    var settings: Settings
    var watchlist: [String]
    var schema: Schema

    static var `default`: AppConfig {
        AppConfig(
            settings: Settings(
                removeDuplicate: true,
                renameByAi: true,
                renameAi: "gemma3:4b",
                ocrAi: "deepocr"
            ),
            watchlist: [],
            schema: Schema(
                move: Move(url: [:], tag: [:]),
                rename: []
            )
        )
    }
}
