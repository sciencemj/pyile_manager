//
//  FileEventTests.swift
//  pyile_managerTests
//

import XCTest
@testable import pyile_manager

final class FileEventTests: XCTestCase {

    func testCodableRoundTripPreservesIdentity() throws {
        let group = UUID()
        let event = FileEvent(
            type: "file_moved",
            timestamp: 1750000000,
            groupID: group,
            filename: "doc.pdf",
            from: "/Users/x/Downloads/doc.pdf",
            to: "/Users/x/Documents/doc.pdf",
            destination: "/Users/x/Documents"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(FileEvent.self, from: data)

        XCTAssertEqual(decoded.id, event.id)            // id must round-trip, not regenerate
        XCTAssertEqual(decoded.groupID, group)
        XCTAssertEqual(decoded.type, "file_moved")
        XCTAssertEqual(decoded.from, "/Users/x/Downloads/doc.pdf")
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testUndoRecordRoundTrip() throws {
        let target = UUID()
        let undo = FileEvent(type: "undo", timestamp: 1750000001, ref: target)

        let data = try JSONEncoder().encode(undo)
        let decoded = try JSONDecoder().decode(FileEvent.self, from: data)

        XCTAssertEqual(decoded.type, "undo")
        XCTAssertEqual(decoded.ref, target)
    }
}
