//
//  HistoryStoreTests.swift
//  pyile_managerTests
//

import XCTest
@testable import pyile_manager

final class HistoryStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeEvent(_ name: String) -> FileEvent {
        FileEvent(type: "file_moved", timestamp: Date().timeIntervalSince1970,
                  filename: name, from: "/src/\(name)", to: "/dst/\(name)", destination: "/dst")
    }

    func testAppendAndLoadRoundTrip() async throws {
        let store = HistoryStore(directory: tempDir)
        let event = makeEvent("a.pdf")

        await store.append(event)
        let entries = await store.loadRecent(limit: 10)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].event.id, event.id)
        XCTAssertFalse(entries[0].undone)
    }

    func testLoadRecentReturnsNewestFirstAndRespectsLimit() async throws {
        let store = HistoryStore(directory: tempDir)
        let first = makeEvent("first.pdf")
        let second = makeEvent("second.pdf")
        let third = makeEvent("third.pdf")
        await store.append(first)
        await store.append(second)
        await store.append(third)

        let entries = await store.loadRecent(limit: 2)

        XCTAssertEqual(entries.map { $0.event.filename }, ["third.pdf", "second.pdf"])
    }

    func testUndoRecordMarksEventUndone() async throws {
        let store = HistoryStore(directory: tempDir)
        let event = makeEvent("a.pdf")
        await store.append(event)
        await store.appendUndo(of: event.id)

        let entries = await store.loadRecent(limit: 10)

        // The undo record itself is not displayed; the original event is marked undone
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].undone)
    }

    func testMalformedLinesAreSkipped() async throws {
        // Simulate a partial/corrupt line from a crash mid-append
        let logURL = tempDir.appendingPathComponent("history.jsonl")
        try "{\"this is\": not json\n".write(to: logURL, atomically: true, encoding: .utf8)

        let store = HistoryStore(directory: tempDir)
        await store.append(makeEvent("good.pdf"))
        let entries = await store.loadRecent(limit: 10)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].event.filename, "good.pdf")
    }

    func testRotationArchivesOversizedLog() async throws {
        let logURL = tempDir.appendingPathComponent("history.jsonl")
        // Pre-create an oversized (>1 MB) log
        let bigLine = String(repeating: "x", count: 1024) + "\n"
        try String(repeating: bigLine, count: 1100).write(to: logURL, atomically: true, encoding: .utf8)

        let store = HistoryStore(directory: tempDir)  // init rotates
        await store.append(makeEvent("fresh.pdf"))
        let entries = await store.loadRecent(limit: 10)

        XCTAssertEqual(entries.count, 1)  // old content rotated away
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("history.1.jsonl").path))
    }

    func testLoadRecentOrdersByTimestampNotFileOrder() async throws {
        let store = HistoryStore(directory: tempDir)
        // Append out of chronological order (simulating racing fire-and-forget tasks)
        let older = FileEvent(type: "file_moved", timestamp: 100,
                              filename: "older.pdf", from: "/src/older.pdf", to: "/dst/older.pdf", destination: "/dst")
        let newer = FileEvent(type: "file_moved", timestamp: 200,
                              filename: "newer.pdf", from: "/src/newer.pdf", to: "/dst/newer.pdf", destination: "/dst")
        await store.append(newer)
        await store.append(older)

        let entries = await store.loadRecent(limit: 10)

        XCTAssertEqual(entries.map { $0.event.filename }, ["newer.pdf", "older.pdf"])
    }

    func testRotationTriggersMidSessionWhenLogGrowsPastThreshold() async throws {
        let logURL = tempDir.appendingPathComponent("history.jsonl")
        // Just under 1 MB: init must NOT rotate
        try String(repeating: "x", count: 1_048_500).write(to: logURL, atomically: true, encoding: .utf8)

        let store = HistoryStore(directory: tempDir)
        let archiveURL = tempDir.appendingPathComponent("history.1.jsonl")
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))

        // First append crosses the threshold; second append triggers rotation
        await store.append(makeEvent("crosser.pdf"))
        await store.append(makeEvent("fresh.pdf"))
        let entries = await store.loadRecent(limit: 10)

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(entries.map { $0.event.filename }, ["fresh.pdf"])
    }
}
