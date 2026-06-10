//
//  FileMoverTests.swift
//  pyile_managerTests
//

import XCTest
@testable import pyile_manager

final class FileMoverTests: XCTestCase {
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

    private func makeFile(_ name: String, in dir: URL, contents: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testNoCollisionMovesNormally() throws {
        let source = try makeFile("doc.txt", in: sourceDir, contents: "hello")

        let result = FileMover.moveFile(at: source, to: destDir, removeDuplicate: true)

        guard case .moved(let newURL) = result else {
            return XCTFail("Expected .moved, got \(result)")
        }
        XCTAssertEqual(newURL.lastPathComponent, "doc.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testIdenticalDuplicateIsTrashed() throws {
        let source = try makeFile("doc.txt", in: sourceDir, contents: "identical")
        _ = try makeFile("doc.txt", in: destDir, contents: "identical")

        let result = FileMover.moveFile(at: source, to: destDir, removeDuplicate: true)

        guard case .duplicateTrashed(let trashURL) = result else {
            return XCTFail("Expected .duplicateTrashed, got \(result)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        // trashItem returned the real Trash location and the file is there
        let trashURLUnwrapped = try XCTUnwrap(trashURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURLUnwrapped.path))
    }

    func testIdenticalDuplicateSkippedWhenRemoveDisabled() throws {
        let source = try makeFile("doc.txt", in: sourceDir, contents: "identical")
        _ = try makeFile("doc.txt", in: destDir, contents: "identical")

        let result = FileMover.moveFile(at: source, to: destDir, removeDuplicate: false)

        guard case .duplicateSkipped = result else {
            return XCTFail("Expected .duplicateSkipped, got \(result)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testSameNameDifferentContentKeepsBoth() throws {
        let source = try makeFile("doc.txt", in: sourceDir, contents: "new version")
        let existing = try makeFile("doc.txt", in: destDir, contents: "old version")

        let result = FileMover.moveFile(at: source, to: destDir, removeDuplicate: true)

        guard case .moved(let newURL) = result else {
            return XCTFail("Expected .moved, got \(result)")
        }
        // Existing file untouched
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "old version")
        // Incoming file kept under a disambiguated name
        XCTAssertNotEqual(newURL.lastPathComponent, "doc.txt")
        XCTAssertTrue(newURL.lastPathComponent.hasPrefix("doc-"))
        XCTAssertTrue(newURL.lastPathComponent.hasSuffix(".txt"))
        XCTAssertEqual(try String(contentsOf: newURL, encoding: .utf8), "new version")
    }
}
