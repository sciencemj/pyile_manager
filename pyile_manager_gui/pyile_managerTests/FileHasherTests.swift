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

    private func makeBinaryFile(_ name: String, bytes: Data) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try bytes.write(to: url)
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

    func testEmptyFilesCompareEqual() throws {
        let a = try makeFile("a.txt", contents: "")
        let b = try makeFile("b.txt", contents: "")
        XCTAssertTrue(FileHasher.contentsAreIdentical(a, b))
    }

    func testLargeMultiChunkIdenticalFilesCompareEqual() throws {
        // ~2.5 MB: forces the 1 MB chunk loop through multiple iterations
        let contents = Data((0..<2_621_440).map { UInt8($0 % 251) })
        let a = try makeBinaryFile("big_a.bin", bytes: contents)
        let b = try makeBinaryFile("big_b.bin", bytes: contents)
        XCTAssertTrue(FileHasher.contentsAreIdentical(a, b))
    }

    func testLargeFilesDifferingOnlyInFinalChunkCompareNotEqual() throws {
        let contentsA = Data((0..<2_621_440).map { UInt8($0 % 251) })
        var contentsB = contentsA
        contentsB[contentsB.count - 1] ^= 0xFF  // flip one bit in the last chunk
        let a = try makeBinaryFile("big_a.bin", bytes: contentsA)
        let b = try makeBinaryFile("big_b.bin", bytes: contentsB)
        XCTAssertFalse(FileHasher.contentsAreIdentical(a, b))
    }
}
