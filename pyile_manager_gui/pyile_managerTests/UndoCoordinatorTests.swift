//
//  UndoCoordinatorTests.swift
//  pyile_managerTests
//

import XCTest
@testable import pyile_manager

final class UndoCoordinatorTests: XCTestCase {
    var sourceDir: URL!
    var destDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sourceDir = base.appendingPathComponent("source")
        destDir = base.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
    }

    private func makeFile(_ name: String, in dir: URL, contents: String = "data") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func entry(_ event: FileEvent, undone: Bool = false) -> HistoryEntry {
        HistoryEntry(event: event, undone: undone)
    }

    func testUndoMoveRestoresOriginalLocation() throws {
        let moved = try makeFile("doc.txt", in: destDir)
        let original = sourceDir.appendingPathComponent("doc.txt")
        let event = FileEvent(type: "file_moved", timestamp: 100,
                              filename: "doc.txt", from: original.path, to: moved.path,
                              destination: destDir.path)

        let undoneIDs = try UndoCoordinator.undo(entry(event), in: [entry(event)])

        XCTAssertEqual(undoneIDs, [event.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
    }

    func testUndoRenameRestoresOldName() throws {
        let renamed = try makeFile("new_name.txt", in: destDir)
        let event = FileEvent(type: "file_renamed", timestamp: 100,
                              oldName: "old_name.txt", newName: "new_name.txt",
                              path: destDir.path, fullPath: renamed.path)

        _ = try UndoCoordinator.undo(entry(event), in: [entry(event)])

        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("old_name.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testUndoTrashedDuplicateRestoresFile() throws {
        // Simulate a trashed file with a recorded trash location
        let trashDir = sourceDir.deletingLastPathComponent().appendingPathComponent("fake_trash")
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trashed = try makeFile("doc.txt", in: trashDir)
        let original = sourceDir.appendingPathComponent("doc.txt")
        let event = FileEvent(type: "duplicate_trashed", timestamp: 100,
                              filename: "doc.txt", from: original.path,
                              destination: destDir.path, trashURL: trashed.path)

        _ = try UndoCoordinator.undo(entry(event), in: [entry(event)])

        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testUndoRefusesWhenTargetOccupied() throws {
        let moved = try makeFile("doc.txt", in: destDir, contents: "moved file")
        _ = try makeFile("doc.txt", in: sourceDir, contents: "a NEW file now occupies the original path")
        let event = FileEvent(type: "file_moved", timestamp: 100,
                              filename: "doc.txt",
                              from: sourceDir.appendingPathComponent("doc.txt").path,
                              to: moved.path, destination: destDir.path)

        XCTAssertThrowsError(try UndoCoordinator.undo(entry(event), in: [entry(event)])) { error in
            guard case UndoError.partial(let undone, let cause) = error,
                  case UndoError.targetOccupied = cause else {
                return XCTFail("Expected partial(targetOccupied), got \(error)")
            }
            XCTAssertTrue(undone.isEmpty)
        }
        // Neither file was touched
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "moved file")
    }

    func testUndoRefusesWhenOriginalDirectoryMissing() throws {
        let moved = try makeFile("doc.txt", in: destDir)
        let goneDir = sourceDir.deletingLastPathComponent().appendingPathComponent("never_existed")
        let event = FileEvent(type: "file_moved", timestamp: 100,
                              filename: "doc.txt",
                              from: goneDir.appendingPathComponent("doc.txt").path,
                              to: moved.path, destination: destDir.path)

        XCTAssertThrowsError(try UndoCoordinator.undo(entry(event), in: [entry(event)])) { error in
            guard case UndoError.partial(let undone, let cause) = error,
                  case UndoError.originalLocationMissing = cause else {
                return XCTFail("Expected partial(originalLocationMissing), got \(error)")
            }
            XCTAssertTrue(undone.isEmpty)
        }
        // Directory was NOT auto-created
        XCTAssertFalse(FileManager.default.fileExists(atPath: goneDir.path))
    }

    func testUndoRefusesWhenFileNoLongerAtRecordedPath() throws {
        let event = FileEvent(type: "file_moved", timestamp: 100,
                              filename: "ghost.txt",
                              from: sourceDir.appendingPathComponent("ghost.txt").path,
                              to: destDir.appendingPathComponent("ghost.txt").path,
                              destination: destDir.path)

        XCTAssertThrowsError(try UndoCoordinator.undo(entry(event), in: [entry(event)])) { error in
            guard case UndoError.partial(let undone, let cause) = error,
                  case UndoError.fileNoLongerExists = cause else {
                return XCTFail("Expected partial(fileNoLongerExists), got \(error)")
            }
            XCTAssertTrue(undone.isEmpty)
        }
    }

    func testGroupUndoReversesMoveAndRenameAsUnit() throws {
        // A file was moved source/report.pdf -> dest/report.pdf, then renamed to q4_report.pdf.
        // Current on-disk state: dest/q4_report.pdf
        let current = try makeFile("q4_report.pdf", in: destDir)
        let group = UUID()
        let moveEvent = FileEvent(type: "file_moved", timestamp: 100, groupID: group,
                                  filename: "report.pdf",
                                  from: sourceDir.appendingPathComponent("report.pdf").path,
                                  to: destDir.appendingPathComponent("report.pdf").path,
                                  destination: destDir.path)
        let renameEvent = FileEvent(type: "file_renamed", timestamp: 101, groupID: group,
                                    oldName: "report.pdf", newName: "q4_report.pdf",
                                    path: destDir.path, fullPath: current.path)
        let history = [entry(renameEvent), entry(moveEvent)]

        // Undoing EITHER entry undoes the whole chain, newest first
        let undoneIDs = try UndoCoordinator.undo(entry(moveEvent), in: history)

        XCTAssertEqual(Set(undoneIDs), Set([moveEvent.id, renameEvent.id]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDir.appendingPathComponent("report.pdf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
    }

    func testGroupUndoMidChainFailureReportsPartialProgress() throws {
        // Move source/report.pdf -> dest/report.pdf, then rename to q4_report.pdf.
        // Sabotage the move-back by occupying the original source path.
        let current = try makeFile("q4_report.pdf", in: destDir)
        _ = try makeFile("report.pdf", in: sourceDir, contents: "intruder")
        let group = UUID()
        let moveEvent = FileEvent(type: "file_moved", timestamp: 100, groupID: group,
                                  filename: "report.pdf",
                                  from: sourceDir.appendingPathComponent("report.pdf").path,
                                  to: destDir.appendingPathComponent("report.pdf").path,
                                  destination: destDir.path)
        let renameEvent = FileEvent(type: "file_renamed", timestamp: 101, groupID: group,
                                    oldName: "report.pdf", newName: "q4_report.pdf",
                                    path: destDir.path, fullPath: current.path)
        let history = [entry(renameEvent), entry(moveEvent)]

        XCTAssertThrowsError(try UndoCoordinator.undo(entry(renameEvent), in: history)) { error in
            guard case UndoError.partial(let undone, let cause) = error else {
                return XCTFail("Expected partial, got \(error)")
            }
            // The rename-back succeeded before the move-back failed
            XCTAssertEqual(undone, [renameEvent.id])
            guard case UndoError.targetOccupied = cause else {
                return XCTFail("Expected targetOccupied cause, got \(cause)")
            }
        }
        // Disk state: rename undone (file at intermediate path), move not undone
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("report.pdf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))

        // Resumability: once the caller marks the rename undone, retrying the move
        // event undoes just the remaining step (after the intruder is cleared).
        try FileManager.default.removeItem(at: sourceDir.appendingPathComponent("report.pdf"))
        let updatedHistory = [entry(renameEvent, undone: true), entry(moveEvent)]
        let undoneIDs = try UndoCoordinator.undo(entry(moveEvent), in: updatedHistory)
        XCTAssertEqual(undoneIDs, [moveEvent.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDir.appendingPathComponent("report.pdf").path))
    }

    func testChainExcludesAlreadyUndoneMembers() throws {
        let current = try makeFile("doc.txt", in: destDir)
        let group = UUID()
        let moveEvent = FileEvent(type: "file_moved", timestamp: 100, groupID: group,
                                  filename: "doc.txt",
                                  from: sourceDir.appendingPathComponent("doc.txt").path,
                                  to: current.path, destination: destDir.path)
        let renameEvent = FileEvent(type: "file_renamed", timestamp: 101, groupID: group,
                                    oldName: "doc.txt", newName: "renamed.txt",
                                    path: destDir.path, fullPath: destDir.appendingPathComponent("renamed.txt").path)
        let history = [entry(renameEvent, undone: true), entry(moveEvent)]

        let chain = UndoCoordinator.chainFor(entry(moveEvent), in: history)

        XCTAssertEqual(chain.map { $0.event.id }, [moveEvent.id])
    }

    func testUndoUnknownEventTypeThrowsUnsupported() throws {
        let event = FileEvent(type: "mystery", timestamp: 100)

        XCTAssertThrowsError(try UndoCoordinator.undo(entry(event), in: [entry(event)])) { error in
            guard case UndoError.partial(_, let cause) = error,
                  case UndoError.unsupportedEventType = cause else {
                return XCTFail("Expected partial(unsupportedEventType), got \(error)")
            }
        }
    }
}
