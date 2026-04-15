//
//  FileMonitorService.swift
//  pyile_manager
//
//  FSEvents-based file system monitoring with auto-sort and AI rename
//

import Foundation
import Combine
import CoreServices
import UserNotifications

@MainActor
class FileMonitorService: ObservableObject {
    @Published var isMonitoring = false
    @Published var recentEvents: [FileEvent] = []

    private let configManager: ConfigManager
    private let ollamaService: OllamaService
    private var eventStream: FSEventStreamRef?
    private var recentlyRenamed: Set<String> = []
    private let maxRecentEvents = 10

    private static let tempExtensions: Set<String> = ["crdownload", "tmp", "part"]

    init(configManager: ConfigManager) {
        self.configManager = configManager
        let settings = configManager.config.settings
        self.ollamaService = OllamaService(renameModel: settings.renameAi, ocrModel: settings.ocrAi)
    }

    // MARK: - Public

    func start() {
        guard !isMonitoring else {
            print("Monitor already running")
            return
        }

        let paths = configManager.config.watchlist.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else {
            print("No valid watchlist paths")
            return
        }

        let cfPaths = paths as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.fsEventsCallback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            print("Failed to create FSEventStream")
            return
        }

        eventStream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        isMonitoring = true

        for path in paths {
            print("Monitoring: \(path)")
        }
        print("File monitor started")
    }

    func stop() {
        guard let stream = eventStream, isMonitoring else {
            print("Monitor not running")
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        isMonitoring = false
        print("File monitor stopped")
    }

    func updateConfig() {
        let settings = configManager.config.settings
        ollamaService.renameModel = settings.renameAi
        ollamaService.ocrModel = settings.ocrAi

        if isMonitoring {
            print("Restarting monitor with new configuration...")
            stop()
            start()
        }
    }

    // MARK: - FSEvents Callback

    private static let fsEventsCallback: FSEventStreamCallback = {
        (stream, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in

        guard let info = clientCallBackInfo else { return }
        let monitor = Unmanaged<FileMonitorService>.fromOpaque(info).takeUnretainedValue()

        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
        let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

        for i in 0..<numEvents {
            let path = paths[i]
            let flag = Int(flags[i])

            // Only process file creation events (not directories, not removals)
            let isFile = (flag & kFSEventStreamEventFlagItemIsFile) != 0
            let isCreated = (flag & kFSEventStreamEventFlagItemCreated) != 0
            let isRenamed = (flag & kFSEventStreamEventFlagItemRenamed) != 0

            if isFile && (isCreated || isRenamed) {
                // Verify file actually exists (renamed events fire for both old and new paths)
                guard FileManager.default.fileExists(atPath: path) else { continue }

                Task { @MainActor in
                    await monitor.handleNewFile(at: URL(fileURLWithPath: path))
                }
            }
        }
    }

    // MARK: - File Processing Pipeline

    private func handleNewFile(at fileURL: URL) async {
        let filename = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()

        // Skip temporary download files
        if Self.tempExtensions.contains(ext) { return }

        // Skip hidden files
        if filename.hasPrefix(".") { return }

        // Wait for file to be fully written
        try? await Task.sleep(for: .milliseconds(500))

        // Verify file still exists after delay
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        var currentURL = fileURL

        // Try to sort file by download source URL
        if let sourceURL = MetadataExtractor.getDownloadSourceURL(for: fileURL) {
            if let newURL = await sortFileByURL(fileURL, filename: filename, sourceURL: sourceURL) {
                currentURL = newURL
                try? await Task.sleep(for: .milliseconds(500)) // Wait for file system to settle
            }
        }

        // Check if file should be AI-renamed
        if shouldRenameFile(at: currentURL) {
            await renameFileWithAI(at: currentURL)
        }
    }

    private func sortFileByURL(_ fileURL: URL, filename: String, sourceURL: String) async -> URL? {
        let config = configManager.config

        guard let destination = URLMatcher.matchURL(sourceURL, against: config.schema.move.url) else {
            return nil
        }

        let destDir = URL(fileURLWithPath: destination)
        let result = FileMover.moveFile(
            at: fileURL,
            to: destDir,
            removeDuplicate: config.settings.removeDuplicate
        )

        switch result {
        case .moved(let newURL):
            let event = FileEvent(
                type: "file_moved",
                timestamp: Date().timeIntervalSince1970,
                filename: filename,
                from: fileURL.path,
                to: newURL.path,
                destination: destination
            )
            addEvent(event)
            return newURL

        case .duplicateRemoved:
            print("Duplicate removed: \(filename)")
            return nil

        case .duplicateSkipped:
            print("Duplicate skipped: \(filename)")
            return nil

        case .failed(let error):
            print("Move failed: \(error)")
            return nil
        }
    }

    private func shouldRenameFile(at fileURL: URL) -> Bool {
        let path = fileURL.path

        // Skip recently renamed files
        if recentlyRenamed.contains(path) {
            print("Skipping recently renamed file: \(fileURL.lastPathComponent)")
            recentlyRenamed.remove(path)
            return false
        }

        guard configManager.config.settings.renameByAi else {
            return false
        }

        let fileDir = fileURL.deletingLastPathComponent().path
        for renameDir in configManager.config.schema.rename {
            if fileDir.hasPrefix(renameDir) {
                return true
            }
        }
        return false
    }

    private func renameFileWithAI(at fileURL: URL) async {
        print("AI renaming: \(fileURL.path)")
        guard let newName = await ollamaService.renameFileWithAI(at: fileURL) else {
            print("Failed to rename file: \(fileURL.path)")
            return
        }

        guard let newURL = OllamaService.renameFileOnDisk(at: fileURL, newName: newName) else {
            return
        }

        // Prevent double-rename
        recentlyRenamed.insert(fileURL.path)

        let event = FileEvent(
            type: "file_renamed",
            timestamp: Date().timeIntervalSince1970,
            oldName: fileURL.lastPathComponent,
            newName: newURL.lastPathComponent,
            path: newURL.deletingLastPathComponent().path,
            fullPath: newURL.path
        )
        addEvent(event)
    }

    // MARK: - Events

    private func addEvent(_ event: FileEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxRecentEvents {
            recentEvents = Array(recentEvents.prefix(maxRecentEvents))
        }
        showNotification(for: event)
    }

    private func showNotification(for event: FileEvent) {
        let content = UNMutableNotificationContent()
        content.title = "Pyile Manager"
        content.subtitle = event.type == "file_moved" ? "File Organized" : "File Renamed"
        content.body = event.displayText
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }
}
