//
//  FileHasherTests.swift
//  pyile_managerTests
//

import XCTest
@testable import pyile_manager

final class FileHasherTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String, contents: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testIdenticalContentsCompareEqual() throws {
        let a = try makeFile("a.txt", contents: "same content here")
        let b = try makeFile("b.txt", contents: "same content here")
        XCTAssertTrue(FileHasher.contentsAreIdentical(a, b))
    }

    func testSameSizeDifferentContentCompareNotEqual() throws {
        let a = try makeFile("a.txt", contents: "aaaa")
        let b = try makeFile("b.txt", contents: "bbbb")
        XCTAssertFalse(FileHasher.contentsAreIdentical(a, b))
    }

    func testDifferentSizesCompareNotEqual() throws {
        let a = try makeFile("a.txt", contents: "short")
        let b = try makeFile("b.txt", contents: "much longer content")
        XCTAssertFalse(FileHasher.contentsAreIdentical(a, b))
    }

    func testMissingFileCompareNotEqual() throws {
        let a = try makeFile("a.txt", contents: "exists")
        let missing = tempDir.appendingPathComponent("missing.txt")
        XCTAssertFalse(FileHasher.contentsAreIdentical(a, missing))
    }
}
