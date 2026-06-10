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
    @Published var recentEvents: [HistoryEntry] = []
    @Published var undoError: String?

    private let configManager: ConfigManager
    private let ollamaService: OllamaService
    private let historyStore = HistoryStore()
    private var eventStream: FSEventStreamRef?
    private var recentlyRenamed: Set<String> = []
    private var recentlyMoved: Set<String> = []
    private let maxRecentEvents = 50

    /// While true, the FSEvents callback drops all events (set around undo operations).
    var suspendProcessing = false

    /// Serializes undo operations; a second click while one runs is dropped.
    private var isUndoing = false

    private static let tempExtensions: Set<String> = ["crdownload", "tmp", "part"]

    init(configManager: ConfigManager) {
        self.configManager = configManager
        let settings = configManager.config.settings
        self.ollamaService = OllamaService(renameModel: settings.renameAi, ocrModel: settings.ocrAi)

        // Don't start real FSEvents monitoring inside app-hosted test runs
        if NSClassFromString("XCTestCase") == nil {
            start()
        }

        // Load persisted history asynchronously — never blocks launch,
        // never triggers notifications (only live addEvent does).
        Task { [weak self] in
            guard let self else { return }
            let entries = await self.historyStore.loadRecent(limit: self.maxRecentEvents)
            self.recentEvents = entries
        }
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
            if monitor.suspendProcessing { continue }
            let path = paths[i]
            let flag = Int(flags[i])

            // Only process file creation events (not directories, not removals)
            let isFile = (flag & kFSEventStreamEventFlagItemIsFile) != 0
            let isCreated = (flag & kFSEventStreamEventFlagItemCreated) != 0
            let isRenamed = (flag & kFSEventStreamEventFlagItemRenamed) != 0

            if isFile && (isCreated || isRenamed) {
                // Verify file actually exists (renamed events fire for both old and new paths)
                guard FileManager.default.fileExists(atPath: path) else { continue }

                let fileURL = URL(fileURLWithPath: path)
                let parentDir = fileURL.deletingLastPathComponent().path

                // Only process files directly in watched directories (not subdirectories)
                // This matches Python watchdog's recursive=False behavior
                let watchlist = monitor.configManager.config.watchlist
                guard watchlist.contains(parentDir) else { continue }

                Task { @MainActor in
                    await monitor.handleNewFile(at: fileURL)
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

        // Skip files we just moved here (prevents re-processing at destination)
        if recentlyMoved.contains(fileURL.path) {
            recentlyMoved.remove(fileURL.path)
            return
        }

        // Wait for file to be fully written
        try? await Task.sleep(for: .milliseconds(500))

        // Verify file still exists after delay
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        var currentURL = fileURL
        let groupID = UUID()  // links this file's move + rename for group undo

        // Try to sort file by download source URL
        if let sourceURL = MetadataExtractor.getDownloadSourceURL(for: fileURL) {
            if let newURL = await sortFileByURL(fileURL, filename: filename, sourceURL: sourceURL, groupID: groupID) {
                currentURL = newURL
                try? await Task.sleep(for: .milliseconds(500)) // Wait for file system to settle
            }
        }

        // Check if file still exists (may have been trashed as duplicate)
        guard FileManager.default.fileExists(atPath: currentURL.path) else { return }

        // Check if file should be AI-renamed
        if shouldRenameFile(at: currentURL) {
            await renameFileWithAI(at: currentURL, groupID: groupID)
        }
    }

    private func sortFileByURL(_ fileURL: URL, filename: String, sourceURL: String, groupID: UUID) async -> URL? {
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
            // Track to prevent re-processing at destination
            recentlyMoved.insert(newURL.path)

            let event = FileEvent(
                type: "file_moved",
                timestamp: Date().timeIntervalSince1970,
                groupID: groupID,
                filename: filename,
                from: fileURL.path,
                to: newURL.path,
                destination: destination
            )
            addEvent(event)
            return newURL

        case .duplicateTrashed(let trashURL):
            let event = FileEvent(
                type: "duplicate_trashed",
                timestamp: Date().timeIntervalSince1970,
                groupID: groupID,
                filename: filename,
                from: fileURL.path,
                destination: destination,
                trashURL: trashURL?.path
            )
            addEvent(event)
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

    private func renameFileWithAI(at fileURL: URL, groupID: UUID) async {
        print("AI renaming: \(fileURL.path)")
        guard let newName = await ollamaService.renameFileWithAI(at: fileURL) else {
            print("Failed to rename file: \(fileURL.path)")
            return
        }

        guard let newURL = OllamaService.renameFileOnDisk(at: fileURL, newName: newName) else {
            return
        }

        // Prevent re-processing of the renamed file
        recentlyRenamed.insert(fileURL.path)
        recentlyMoved.insert(newURL.path)

        let event = FileEvent(
            type: "file_renamed",
            timestamp: Date().timeIntervalSince1970,
            groupID: groupID,
            oldName: fileURL.lastPathComponent,
            newName: newURL.lastPathComponent,
            path: newURL.deletingLastPathComponent().path,
            fullPath: newURL.path
        )
        addEvent(event)
    }

    // MARK: - Undo

    func undo(_ entry: HistoryEntry) async {
        // Re-read the live entry: a sibling group-undo may have already
        // flipped it after this row's HistoryEntry value was captured.
        guard let live = recentEvents.first(where: { $0.id == entry.id }), !live.undone else { return }
        guard !isUndoing else { return }
        isUndoing = true
        defer { isUndoing = false }
        suspendProcessing = true

        let snapshot = recentEvents
        // File I/O off the main actor; FileEvent/HistoryEntry are value types.
        let result: Result<[UUID], Error> = await Task.detached {
            do { return .success(try UndoCoordinator.undo(entry, in: snapshot)) }
            catch { return .failure(error) }
        }.value

        switch result {
        case .success(let undoneIDs):
            markUndone(undoneIDs)
            undoError = nil
        case .failure(let error):
            if case UndoError.partial(let undoneIDs, let cause) = error {
                // Mark what DID happen on disk so a retry resumes with the rest
                markUndone(undoneIDs)
                undoError = undoneIDs.isEmpty ? cause.localizedDescription : error.localizedDescription
            } else {
                undoError = error.localizedDescription
            }
        }

        // Let the FSEvents coalescing window (1.0s stream latency) drain
        // before resuming, so the restored file is not re-processed.
        try? await Task.sleep(for: .seconds(2.5))
        suspendProcessing = false
    }

    /// Flip the in-memory flags and persist undo records. Never routes through
    /// addEvent — undo records must not notify or render as events.
    private func markUndone(_ ids: [UUID]) {
        for id in ids {
            if let idx = recentEvents.firstIndex(where: { $0.event.id == id }) {
                recentEvents[idx].undone = true
            }
        }
        Task { [historyStore] in
            for id in ids { await historyStore.appendUndo(of: id) }
        }
    }

    // MARK: - Events

    /// Live events only: persists to the history log and notifies.
    /// History loaded at launch goes straight to recentEvents and never lands here.
    private func addEvent(_ event: FileEvent) {
        recentEvents.insert(HistoryEntry(event: event, undone: false), at: 0)
        if recentEvents.count > maxRecentEvents {
            recentEvents = Array(recentEvents.prefix(maxRecentEvents))
        }
        Task { await historyStore.append(event) }
        showNotification(for: event)
    }

    private func showNotification(for event: FileEvent) {
        let content = UNMutableNotificationContent()
        content.title = "Pyile Manager"
        content.subtitle = {
            switch event.type {
            case "file_moved": return "File Organized"
            case "duplicate_trashed": return "Duplicate Moved to Trash"
            default: return "File Renamed"
            }
        }()
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
