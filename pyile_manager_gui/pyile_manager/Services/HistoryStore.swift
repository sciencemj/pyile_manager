//
//  HistoryStore.swift
//  pyile_manager
//
//  Append-only JSON Lines history at ~/.config/pyile_manager/history.jsonl.
//  Undone-state is event-sourced: an "undo" record references the original
//  event id and is folded over the log at load time. Lines are never rewritten.
//

import Foundation

actor HistoryStore {
    private let fileURL: URL
    private let maxFileSize: UInt64 = 1_048_576  // rotate at 1 MB; bounds load time
    private var currentSize: UInt64 = 0

    /// `directory` is injectable for tests; defaults to the app's config directory.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pyile_manager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.jsonl")
        rotateIfNeeded()
        currentSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64 ?? 0
    }

    func append(_ event: FileEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        appendLine(data)
    }

    func appendUndo(of eventID: UUID) {
        let record = FileEvent(type: "undo", timestamp: Date().timeIntervalSince1970, ref: eventID)
        append(record)
    }

    /// Newest-first entries with undone-state folded from "undo" records.
    /// Malformed lines (e.g. a crash mid-append) are skipped.
    func loadRecent(limit: Int) -> [HistoryEntry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        var events: [FileEvent] = []
        var undoneIDs: Set<UUID> = []

        for line in content.split(separator: "\n") {
            guard let event = try? decoder.decode(FileEvent.self, from: Data(line.utf8)) else { continue }
            if event.type == "undo" {
                if let ref = event.ref { undoneIDs.insert(ref) }
            } else {
                events.append(event)
            }
        }

        // Appends are fire-and-forget tasks, so file order is not guaranteed
        // chronological; sort by timestamp (file order breaks ties).
        let ordered = events.enumerated()
            .sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
            .map(\.element)
        return ordered.suffix(limit).reversed().map {
            HistoryEntry(event: $0, undone: undoneIDs.contains($0.id))
        }
    }

    // MARK: - Private

    private func appendLine(_ data: Data) {
        if currentSize > maxFileSize {
            rotateIfNeeded()
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data + Data("\n".utf8))
            currentSize += UInt64(data.count) + 1
        } catch {
            print("Failed to append history: \(error.localizedDescription)")
        }
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64,
              size > maxFileSize else { return }
        let archived = fileURL.deletingLastPathComponent().appendingPathComponent("history.1.jsonl")
        try? fm.removeItem(at: archived)
        try? fm.moveItem(at: fileURL, to: archived)
        currentSize = 0
        print("History log rotated to history.1.jsonl")
    }
}
