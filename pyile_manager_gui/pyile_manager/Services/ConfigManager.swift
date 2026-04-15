//
//  ConfigManager.swift
//  pyile_manager
//
//  Manages loading and saving application configuration from JSON file
//

import Foundation
import Combine

@MainActor
class ConfigManager: ObservableObject {
    @Published var config: AppConfig

    private let configURL: URL

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pyile_manager")
        self.configURL = configDir.appendingPathComponent("pyile_manager_setting.json")
        self.config = AppConfig.default

        // Ensure config directory exists
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            print("Config file not found, using defaults")
            config = .default
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(AppConfig.self, from: data)
            print("Config loaded from \(configURL.path)")
        } catch {
            print("Error loading config: \(error.localizedDescription)")
            config = .default
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
            print("Config saved to \(configURL.path)")
        } catch {
            print("Error saving config: \(error.localizedDescription)")
        }
    }
}
