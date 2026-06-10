# Organization History & Undo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make pyile_manager's destructive actions recoverable: duplicates go to Trash (never permanently deleted) with content verification, every move/rename/trash action is persisted to an on-disk history, and each history entry gets a one-click Undo.

**Architecture:** Three independently shippable milestones (intended as one PR each). Milestone 1 hardens `FileMover`: size-then-SHA256 content check before treating a name collision as a duplicate, `FileManager.trashItem` instead of `removeItem`, and skip-never-delete on Trash failure. Milestone 2 adds an event-sourced JSON Lines history (`~/.config/pyile_manager/history.jsonl`) behind a `HistoryStore` actor; undo state is computed by folding `undo` records over the log (no in-place line rewrites). Milestone 3 adds `UndoCoordinator` (never overwrites, never auto-creates directories, undoes move+rename chains as a unit via `groupID`), with monitoring suspended around each undo so FSEvents re-fires can't re-process restored files.

**Tech Stack:** Swift 5 / SwiftUI (macOS 13+ MenuBarExtra app), FileManager (`trashItem`), CryptoKit (SHA256), FSEvents, XCTest. No third-party dependencies.

**Background:** The current `FileMover.moveFile` permanently deletes the source file whenever a *same-named* file exists at the destination and `removeDuplicate` is on (the default). "Duplicate" is filename-only — different content with the same name is destroyed. The last three commits on this branch all fixed bugs where FSEvents re-fires caused wrongful deletes. History is 10 in-memory events lost on restart. This plan came out of a reviewed proposal; key review rulings baked in below:

- Trash fallback on error is **skip**, never `removeItem`.
- Always persist the **exact** `resultingItemURL` from `trashItem`; never reconstruct Trash paths.
- JSONL is **append-only**; undone-state is an appended `undo` record folded at load, not a mutated line.
- `FileEvent.id` must round-trip through Codable (no fresh UUID on decode).
- Undo must **pause monitoring** (global suspend flag + drain delay), not reuse the consume-once `recentlyMoved`/`recentlyRenamed` sets.
- Undo must **refuse** when the restore target is occupied or the original directory is missing — never overwrite, never `createDirectory`.
- Move→rename of one physical file shares a `groupID` and undoes as a unit, newest first.
- Undo file I/O runs off the main actor; loaded history and undo records never trigger notifications.
- Out of scope for v1: redo, divergence reconciliation on restore, empty-trash UI, stripping `kMDItemWhereFroms`, tag-based sorting, App Sandbox/bookmarks, blocking launch on history load.

**File structure (whole plan):**

| File | Action | Responsibility |
|------|--------|----------------|
| `pyile_manager_gui/pyile_manager/Services/FileHasher.swift` | Create (M1) | size-then-SHA256 content equality |
| `pyile_manager_gui/pyile_manager/Services/FileMover.swift` | Modify (M1) | trash-not-delete, content-verified duplicates, keep-both on mismatch |
| `pyile_manager_gui/pyile_manager/Models/FileEvent.swift` | Modify (M2) | Codable events + `HistoryEntry`, new `duplicate_trashed`/`undo` types |
| `pyile_manager_gui/pyile_manager/Services/HistoryStore.swift` | Create (M2) | append-only JSONL log, fold-on-load, rotation |
| `pyile_manager_gui/pyile_manager/Services/FileMonitorService.swift` | Modify (M2, M3) | history integration, groupID, suspend flag, undo entry point |
| `pyile_manager_gui/pyile_manager/Services/UndoCoordinator.swift` | Create (M3) | reverse operations with safety checks |
| `pyile_manager_gui/pyile_manager/Views/MenuBarView.swift` | Modify (M2, M3) | HistoryEntry rows, Undo button, View History |
| `pyile_manager_gui/pyile_manager/Views/HistoryWindow.swift` | Create (M3) | full history window with undo + error alert |
| `pyile_manager_gui/pyile_manager/pyile_managerApp.swift` | Modify (M3) | "history" Window scene |
| `pyile_manager_gui/pyile_managerTests/*` | Create (M1–M3) | XCTest unit tests |

All builds/tests run with:

```bash
xcodebuild build -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet
xcodebuild test  -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet
```

---

## Milestone 1 — Safe duplicate handling (ship as PR 1)

Removes the single most dangerous line in the codebase. After this milestone: name collisions with *different* content keep both files; *identical* content goes to Trash (recoverable), and a Trash failure skips instead of deleting.

### Task 1: Add the unit test target

**Files:**
- Modify: `pyile_manager_gui/pyile_manager.xcodeproj` (via Xcode GUI — do not hand-edit pbxproj)

The project currently has no test target. Adding one is a GUI operation:

- [ ] **Step 1: Create the target in Xcode**

1. Open `pyile_manager_gui/pyile_manager.xcodeproj` in Xcode.
2. File → New → Target… → macOS → **Unit Testing Bundle**.
3. Product Name: `pyile_managerTests`. Target to be tested: `pyile_manager`. Finish.
4. Xcode adds the target to the `pyile_manager` scheme's Test action automatically — verify under Product → Scheme → Edit Scheme… → Test.

- [ ] **Step 2: Verify the empty test target runs**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **` (the template test passes).

- [ ] **Step 3: Delete the template test file and commit**

Delete the generated `pyile_managerTests/pyile_managerTests.swift` template (we write real tests next task).

```bash
git add pyile_manager_gui
git commit -m "test: add pyile_managerTests unit test target

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 2: FileHasher — content equality

**Files:**
- Create: `pyile_manager_gui/pyile_manager/Services/FileHasher.swift`
- Test: `pyile_manager_gui/pyile_managerTests/FileHasherTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: BUILD FAILED — `cannot find 'FileHasher' in scope`.

- [ ] **Step 3: Implement FileHasher**

```swift
//
//  FileHasher.swift
//  pyile_manager
//
//  Content equality: size check first, SHA-256 only when sizes match
//

import Foundation
import CryptoKit

struct FileHasher {

    /// True only when both files exist and have byte-identical contents.
    static func contentsAreIdentical(_ a: URL, _ b: URL) -> Bool {
        let fm = FileManager.default
        guard let sizeA = (try? fm.attributesOfItem(atPath: a.path))?[.size] as? UInt64,
              let sizeB = (try? fm.attributesOfItem(atPath: b.path))?[.size] as? UInt64,
              sizeA == sizeB else {
            return false
        }
        guard let hashA = sha256(of: a), let hashB = sha256(of: b) else { return false }
        return hashA == hashB
    }

    /// Streaming SHA-256 (1 MB chunks) so large files don't load into memory.
    private static func sha256(of url: URL) -> SHA256.Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`, 4 tests passed.

- [ ] **Step 5: Commit**

```bash
git add pyile_manager_gui/pyile_manager/Services/FileHasher.swift pyile_manager_gui/pyile_managerTests/FileHasherTests.swift
git commit -m "feat: add FileHasher for size-then-SHA256 content comparison

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 3: FileMover — trash, verify, keep-both

**Files:**
- Modify: `pyile_manager_gui/pyile_manager/Services/FileMover.swift` (whole file replaced below)
- Modify: `pyile_manager_gui/pyile_manager/Services/FileMonitorService.swift:214-216` (switch case rename)
- Test: `pyile_manager_gui/pyile_managerTests/FileMoverTests.swift`

Behavior change summary: `.duplicateRemoved` case becomes `.duplicateTrashed(trashURL: URL?)`. A name collision is only a "duplicate" when contents are identical; otherwise the incoming file is kept with a timestamp-suffixed name (same convention `OllamaService.renameFileOnDisk` already uses).

- [ ] **Step 1: Write the failing tests**

Note: `testIdenticalDuplicateIsTrashed` really puts a small file in the user's Trash on each run; that is expected and harmless.

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: BUILD FAILED — `type 'FileMover.MoveResult' has no member 'duplicateTrashed'`.

- [ ] **Step 3: Replace FileMover.swift**

```swift
//
//  FileMover.swift
//  pyile_manager
//
//  File moving with content-verified duplicate detection.
//  Duplicates are moved to Trash (recoverable), never permanently deleted.
//

import Foundation

struct FileMover {

    enum MoveResult {
        case moved(URL)                     // Successfully moved, new URL
        case duplicateTrashed(trashURL: URL?) // Identical content existed; source moved to Trash
        case duplicateSkipped               // Identical content existed; removal disabled or Trash unavailable
        case failed(String)                 // Error message
    }

    /// Move a file to a destination directory.
    /// A name collision counts as a duplicate only when file contents are identical;
    /// otherwise the incoming file is kept under a timestamp-suffixed name.
    static func moveFile(at source: URL, to destinationDir: URL, removeDuplicate: Bool) -> MoveResult {
        let fm = FileManager.default
        let filename = source.lastPathComponent
        var destPath = destinationDir.appendingPathComponent(filename)

        // Create destination directory if needed
        do {
            try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        } catch {
            return .failed("Failed to create directory: \(error.localizedDescription)")
        }

        if fm.fileExists(atPath: destPath.path) {
            if FileHasher.contentsAreIdentical(source, destPath) {
                // True duplicate (same content)
                guard removeDuplicate else { return .duplicateSkipped }

                var trashedURL: NSURL?
                do {
                    try fm.trashItem(at: source, resultingItemURL: &trashedURL)
                    print("Duplicate moved to Trash: \(filename)")
                    return .duplicateTrashed(trashURL: trashedURL as URL?)
                } catch {
                    // Some volumes have no Trash. Never fall back to permanent deletion.
                    print("Trash unavailable for \(filename) (\(error.localizedDescription)) — keeping file")
                    return .duplicateSkipped
                }
            }
            // Same name, different content — keep both
            destPath = disambiguatedDestination(for: filename, in: destinationDir)
        }

        do {
            try fm.moveItem(at: source, to: destPath)
            print("File moved: \(filename) -> \(destinationDir.path)")
            return .moved(destPath)
        } catch {
            return .failed("Failed to move file: \(error.localizedDescription)")
        }
    }

    /// "doc.txt" -> "doc-20260610-153000.txt" (same convention as renameFileOnDisk collisions)
    private static func disambiguatedDestination(for filename: String, in dir: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let newName = ext.isEmpty ? "\(base)-\(stamp)" : "\(base)-\(stamp).\(ext)"
        return dir.appendingPathComponent(newName)
    }
}
```

- [ ] **Step 4: Update the switch in FileMonitorService**

In `pyile_manager_gui/pyile_manager/Services/FileMonitorService.swift`, `sortFileByURL`, replace:

```swift
        case .duplicateRemoved:
            print("Duplicate removed: \(filename)")
            return nil
```

with:

```swift
        case .duplicateTrashed(let trashURL):
            print("Duplicate moved to Trash: \(filename) -> \(trashURL?.path ?? "unknown")")
            return nil
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`, 8 tests passed (4 FileHasher + 4 FileMover).

- [ ] **Step 6: Commit**

```bash
git add pyile_manager_gui/pyile_manager/Services/FileMover.swift pyile_manager_gui/pyile_manager/Services/FileMonitorService.swift pyile_manager_gui/pyile_managerTests/FileMoverTests.swift
git commit -m "feat: trash duplicates instead of deleting, verify by content

Name collisions are only duplicates when contents are identical
(size-then-SHA256). Identical files go to macOS Trash via trashItem;
on Trash failure the file is kept, never permanently deleted. Same
name with different content now keeps both files.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

**Milestone 1 done — shippable as PR 1.**

---

## Milestone 2 — Persistent history (ship as PR 2)

Event-sourced JSONL log at `~/.config/pyile_manager/history.jsonl`. The menu bar list survives restarts; duplicate-trash actions become visible events; move+rename of one file share a `groupID` (consumed by Milestone 3).

### Task 4: FileEvent becomes Codable; add HistoryEntry

**Files:**
- Modify: `pyile_manager_gui/pyile_manager/Models/FileEvent.swift` (whole file replaced below)
- Test: `pyile_manager_gui/pyile_managerTests/FileEventTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: BUILD FAILED — `extra arguments at positions ... in call` / `FileEvent does not conform to Codable`.

- [ ] **Step 3: Replace FileEvent.swift**

```swift
//
//  FileEvent.swift
//  pyile_manager
//
//  File event models for monitoring, persistent history, and undo
//

import Foundation

struct FileEvent: Identifiable, Codable {
    var schemaVersion: Int = 1
    let id: UUID
    let type: String  // "file_moved", "file_renamed", "duplicate_trashed", "undo"
    let timestamp: Double

    /// Links the move and rename of one physical file so they undo as a unit.
    let groupID: UUID?

    // For file_moved and duplicate_trashed events
    let filename: String?
    let from: String?
    let to: String?
    let destination: String?

    // For file_renamed events
    let oldName: String?
    let newName: String?
    let path: String?
    let fullPath: String?

    // For duplicate_trashed events: the exact URL trashItem reported
    let trashURL: String?

    // For undo records: the id of the event that was undone
    let ref: UUID?

    init(type: String, timestamp: Double, groupID: UUID? = nil,
         filename: String? = nil, from: String? = nil, to: String? = nil, destination: String? = nil,
         oldName: String? = nil, newName: String? = nil, path: String? = nil, fullPath: String? = nil,
         trashURL: String? = nil, ref: UUID? = nil) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.groupID = groupID
        self.filename = filename
        self.from = from
        self.to = to
        self.destination = destination
        self.oldName = oldName
        self.newName = newName
        self.path = path
        self.fullPath = fullPath
        self.trashURL = trashURL
        self.ref = ref
    }

    // Human-readable description
    var displayText: String {
        switch type {
        case "file_moved":
            return "\(filename ?? "File") → \(destination ?? "Unknown")"
        case "file_renamed":
            return "\(oldName ?? "File") → \(newName ?? "Unknown")"
        case "duplicate_trashed":
            return "\(filename ?? "File") → Trash (duplicate)"
        default:
            return "Unknown event"
        }
    }

    var displayIcon: String {
        switch type {
        case "file_moved":
            return "arrow.right.square"
        case "file_renamed":
            return "pencil.circle"
        case "duplicate_trashed":
            return "trash.circle"
        default:
            return "questionmark.circle"
        }
    }
}

/// A history event plus its computed undone-state (folded from "undo" records).
struct HistoryEntry: Identifiable {
    let event: FileEvent
    var undone: Bool
    var id: UUID { event.id }
}
```

Note: the synthesized `Codable` conformance encodes every stored property including `id` — the custom `init` only controls creation, not decoding, so decoded events keep their original `id`. That is exactly what the first test asserts.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add pyile_manager_gui/pyile_manager/Models/FileEvent.swift pyile_manager_gui/pyile_managerTests/FileEventTests.swift
git commit -m "feat: make FileEvent Codable with stable id, groupID, trash/undo fields

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 5: HistoryStore — append-only JSONL with fold-on-load

**Files:**
- Create: `pyile_manager_gui/pyile_manager/Services/HistoryStore.swift`
- Test: `pyile_manager_gui/pyile_managerTests/HistoryStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: BUILD FAILED — `cannot find 'HistoryStore' in scope`.

- [ ] **Step 3: Implement HistoryStore**

```swift
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

    /// `directory` is injectable for tests; defaults to the app's config directory.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pyile_manager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.jsonl")
        rotateIfNeeded()
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

        return events.suffix(limit).reversed().map {
            HistoryEntry(event: $0, undone: undoneIDs.contains($0.id))
        }
    }

    // MARK: - Private

    private func appendLine(_ data: Data) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data + Data("\n".utf8))
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
        print("History log rotated to history.1.jsonl")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add pyile_manager_gui/pyile_manager/Services/HistoryStore.swift pyile_manager_gui/pyile_managerTests/HistoryStoreTests.swift
git commit -m "feat: add event-sourced JSONL HistoryStore with rotation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 6: Wire history into the pipeline and menu bar

**Files:**
- Modify: `pyile_manager_gui/pyile_manager/Services/FileMonitorService.swift`
- Modify: `pyile_manager_gui/pyile_manager/Views/MenuBarView.swift`

No new unit tests here (UI + actor glue); verified by build + manual run at the end of the task.

- [ ] **Step 1: Update FileMonitorService state and init**

Replace the property block (`@Published var recentEvents...` / `maxRecentEvents`) and `init` so they read:

```swift
    @Published var isMonitoring = false
    @Published var recentEvents: [HistoryEntry] = []

    private let configManager: ConfigManager
    private let ollamaService: OllamaService
    private let historyStore = HistoryStore()
    private var eventStream: FSEventStreamRef?
    private var recentlyRenamed: Set<String> = []
    private var recentlyMoved: Set<String> = []
    private let maxRecentEvents = 50

    private static let tempExtensions: Set<String> = ["crdownload", "tmp", "part"]

    init(configManager: ConfigManager) {
        self.configManager = configManager
        let settings = configManager.config.settings
        self.ollamaService = OllamaService(renameModel: settings.renameAi, ocrModel: settings.ocrAi)
        start()

        // Load persisted history asynchronously — never blocks launch,
        // never triggers notifications (only live addEvent does).
        Task { [weak self] in
            guard let self else { return }
            let entries = await self.historyStore.loadRecent(limit: self.maxRecentEvents)
            self.recentEvents = entries
        }
    }
```

- [ ] **Step 2: Thread a groupID through the pipeline**

Replace `handleNewFile`'s sorting/renaming tail (from `var currentURL = fileURL` to the end of the function) with:

```swift
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
```

- [ ] **Step 3: Update sortFileByURL to record events (including duplicate_trashed)**

Replace `sortFileByURL` with:

```swift
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
```

(Note the `FileEvent` init's parameter order: `trashURL:` comes after the rename-related parameters; with the labeled defaults this call is valid as written.)

- [ ] **Step 4: Update renameFileWithAI and addEvent**

Replace `renameFileWithAI` and `addEvent` with:

```swift
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
```

Also update `showNotification`'s subtitle line to handle the new type:

```swift
        content.subtitle = {
            switch event.type {
            case "file_moved": return "File Organized"
            case "duplicate_trashed": return "Duplicate Moved to Trash"
            default: return "File Renamed"
            }
        }()
```

- [ ] **Step 5: Update MenuBarView for HistoryEntry**

In `pyile_manager_gui/pyile_manager/Views/MenuBarView.swift`, replace the `ForEach` line:

```swift
                            ForEach(Array(fileMonitor.recentEvents.prefix(5))) { entry in
                                EventRow(entry: entry)
                            }
```

and replace `EventRow` with:

```swift
struct EventRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.event.displayIcon)
                .foregroundStyle(entry.event.type == "file_moved" ? .blue : .green)
                .font(.caption)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.event.displayText)
                    .font(.caption)
                    .lineLimit(1)
                    .strikethrough(entry.undone)
                    .foregroundStyle(entry.undone ? .secondary : .primary)
                Text(timeAgo(from: entry.event.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    private func timeAgo(from timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let seconds = Date().timeIntervalSince(date)

        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}
```

- [ ] **Step 6: Build and run all tests**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Manual verification**

1. Run the app from Xcode. Drop a file with download metadata into a watched folder; confirm the move appears in the menu bar.
2. Quit and relaunch the app. Expected: the same event is still listed (loaded from `~/.config/pyile_manager/history.jsonl`) and **no notification fires for it**.
3. `cat ~/.config/pyile_manager/history.jsonl` — expected: one JSON object per line.

- [ ] **Step 8: Commit**

```bash
git add pyile_manager_gui/pyile_manager/Services/FileMonitorService.swift pyile_manager_gui/pyile_manager/Views/MenuBarView.swift
git commit -m "feat: persist file events to history log, survive restarts

Events now carry a groupID linking a file's move and rename.
Duplicate-trash actions are recorded as visible events. History
loads asynchronously on launch without notifications.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

**Milestone 2 done — shippable as PR 2.**

---

## Milestone 3 — One-click Undo (ship as PR 3)

### Task 7: UndoCoordinator — safe reverse operations

**Files:**
- Create: `pyile_manager_gui/pyile_manager/Services/UndoCoordinator.swift`
- Test: `pyile_manager_gui/pyile_managerTests/UndoCoordinatorTests.swift`

Safety invariants (all tested): never overwrite an occupied restore target; never create a missing original directory; undo a move+rename group as a unit, newest first.

- [ ] **Step 1: Write the failing tests**

```swift
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
            guard case UndoError.targetOccupied = error else {
                return XCTFail("Expected targetOccupied, got \(error)")
            }
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
            guard case UndoError.originalLocationMissing = error else {
                return XCTFail("Expected originalLocationMissing, got \(error)")
            }
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
            guard case UndoError.fileNoLongerExists = error else {
                return XCTFail("Expected fileNoLongerExists, got \(error)")
            }
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: BUILD FAILED — `cannot find 'UndoCoordinator' in scope`.

- [ ] **Step 3: Implement UndoCoordinator**

```swift
//
//  UndoCoordinator.swift
//  pyile_manager
//
//  Reverses recorded file events. Safety invariants:
//  - never overwrites an occupied restore target
//  - never creates a missing original directory
//  - move+rename chains (shared groupID) undo as a unit, newest first
//

import Foundation

enum UndoError: LocalizedError {
    case fileNoLongerExists(String)
    case originalLocationMissing(String)
    case targetOccupied(String)
    case unsupportedEventType(String)

    var errorDescription: String? {
        switch self {
        case .fileNoLongerExists(let path):
            return "Cannot undo: the file is no longer at \(path)."
        case .originalLocationMissing(let dir):
            return "Cannot undo: the original folder \(dir) no longer exists."
        case .targetOccupied(let path):
            return "Cannot undo: another file now exists at \(path)."
        case .unsupportedEventType(let type):
            return "Cannot undo event of type \(type)."
        }
    }
}

struct UndoCoordinator {

    /// Undo an entry. If the entry belongs to a group (move+rename of one file),
    /// the whole not-yet-undone group is reversed, newest first.
    /// Returns the ids of all events that were undone.
    static func undo(_ entry: HistoryEntry, in history: [HistoryEntry]) throws -> [UUID] {
        let chain = chainFor(entry, in: history)
        for item in chain {
            try undoSingle(item.event)
        }
        return chain.map { $0.event.id }
    }

    /// All not-yet-undone events sharing the entry's groupID, newest first.
    static func chainFor(_ entry: HistoryEntry, in history: [HistoryEntry]) -> [HistoryEntry] {
        guard let groupID = entry.event.groupID else { return [entry] }
        let chain = history
            .filter { $0.event.groupID == groupID && !$0.undone && $0.event.type != "undo" }
            .sorted { $0.event.timestamp > $1.event.timestamp }
        return chain.isEmpty ? [entry] : chain
    }

    // MARK: - Private

    private static func undoSingle(_ event: FileEvent) throws {
        switch event.type {
        case "file_moved":
            guard let from = event.from, let to = event.to else {
                throw UndoError.unsupportedEventType(event.type)
            }
            try moveBack(current: to, original: from)

        case "file_renamed":
            guard let dir = event.path, let oldName = event.oldName, let fullPath = event.fullPath else {
                throw UndoError.unsupportedEventType(event.type)
            }
            let original = (dir as NSString).appendingPathComponent(oldName)
            try moveBack(current: fullPath, original: original)

        case "duplicate_trashed":
            guard let trashPath = event.trashURL, let original = event.from else {
                throw UndoError.unsupportedEventType(event.type)
            }
            try moveBack(current: trashPath, original: original)

        default:
            throw UndoError.unsupportedEventType(event.type)
        }
    }

    private static func moveBack(current: String, original: String) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: current) else {
            throw UndoError.fileNoLongerExists(current)
        }

        let originalDir = (original as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: originalDir, isDirectory: &isDir), isDir.boolValue else {
            // Never auto-create: it could land on the wrong volume or
            // resurrect a path the user deleted on purpose.
            throw UndoError.originalLocationMissing(originalDir)
        }

        guard !fm.fileExists(atPath: original) else {
            throw UndoError.targetOccupied(original)
        }

        try fm.moveItem(atPath: current, toPath: original)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add pyile_manager_gui/pyile_manager/Services/UndoCoordinator.swift pyile_manager_gui/pyile_managerTests/UndoCoordinatorTests.swift
git commit -m "feat: add UndoCoordinator with overwrite/missing-dir refusal and group undo

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 8: FileMonitorService.undo with monitoring suspension

**Files:**
- Modify: `pyile_manager_gui/pyile_manager/Services/FileMonitorService.swift`

Why suspension: undo moves files back **into watched folders**. The file still carries its `kMDItemWhereFroms` metadata, so FSEvents would re-fire and the pipeline would immediately re-sort (or re-AI-rename) it — undoing the undo. The existing `recentlyMoved`/`recentlyRenamed` sets are consume-once and FSEvents coalesces/re-fires within its 1.0 s latency window (the cause of the three earlier delete-loop bugs), so they are NOT sufficient. A global suspend flag plus a 2.5 s drain (>2× the stream latency) is the robust mechanism.

- [ ] **Step 1: Add the suspend flag and undo entry point**

Add to `FileMonitorService`'s properties:

```swift
    @Published var undoError: String?
    /// While true, the FSEvents callback drops all events (set around undo operations).
    var suspendProcessing = false
```

Add this method after `renameFileWithAI`:

```swift
    // MARK: - Undo

    func undo(_ entry: HistoryEntry) async {
        guard !entry.undone else { return }
        suspendProcessing = true

        let snapshot = recentEvents
        // File I/O off the main actor; FileEvent/HistoryEntry are value types.
        let result: Result<[UUID], Error> = await Task.detached {
            do { return .success(try UndoCoordinator.undo(entry, in: snapshot)) }
            catch { return .failure(error) }
        }.value

        switch result {
        case .success(let undoneIDs):
            for id in undoneIDs {
                if let idx = recentEvents.firstIndex(where: { $0.event.id == id }) {
                    recentEvents[idx].undone = true
                }
            }
            Task { [historyStore] in
                for id in undoneIDs { await historyStore.appendUndo(of: id) }
            }
            undoError = nil
        case .failure(let error):
            undoError = error.localizedDescription
        }

        // Let the FSEvents coalescing window (1.0s stream latency) drain
        // before resuming, so the restored file is not re-processed.
        try? await Task.sleep(for: .seconds(2.5))
        suspendProcessing = false
    }
```

- [ ] **Step 2: Drop events while suspended**

In the `fsEventsCallback` closure, at the top of the `for i in 0..<numEvents` loop body (before `let path = paths[i]`), add:

```swift
            if monitor.suspendProcessing { continue }
```

(The callback is scheduled on the main run loop — same thread as the `@MainActor` service — so this read is safe, matching the existing direct access to `monitor.configManager`.)

- [ ] **Step 3: Build**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **` (existing tests still pass; this step is glue, exercised manually in Task 9).

- [ ] **Step 4: Commit**

```bash
git add pyile_manager_gui/pyile_manager/Services/FileMonitorService.swift
git commit -m "feat: add undo entry point with FSEvents suspension and drain delay

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 9: Undo UI — menu bar buttons and History window

**Files:**
- Modify: `pyile_manager_gui/pyile_manager/Views/MenuBarView.swift`
- Create: `pyile_manager_gui/pyile_manager/Views/HistoryWindow.swift`
- Modify: `pyile_manager_gui/pyile_manager/pyile_managerApp.swift`

- [ ] **Step 1: Add the undo action to EventRow and the menu bar list**

In `MenuBarView.swift`, replace the `ForEach` with:

```swift
                            ForEach(Array(fileMonitor.recentEvents.prefix(5))) { entry in
                                EventRow(entry: entry) {
                                    Task { await fileMonitor.undo(entry) }
                                }
                            }
```

Replace `EventRow`'s declaration and body's `HStack` with (only the marked parts change — `onUndo` property and the undo button before `Spacer()`):

```swift
struct EventRow: View {
    let entry: HistoryEntry
    var onUndo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.event.displayIcon)
                .foregroundStyle(entry.event.type == "file_moved" ? .blue : .green)
                .font(.caption)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.event.displayText)
                    .font(.caption)
                    .lineLimit(1)
                    .strikethrough(entry.undone)
                    .foregroundStyle(entry.undone ? .secondary : .primary)
                Text(timeAgo(from: entry.event.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onUndo, !entry.undone {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .help("Undo")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    // timeAgo(from:) unchanged from Task 6
```

Add a "View History" button in the Actions `VStack`, directly below the "Open Settings" button:

```swift
                Button(action: openHistoryWindow) {
                    Label("View History", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
```

and the action method next to `openSettingsWindow()`:

```swift
    private func openHistoryWindow() {
        openWindow(id: "history")
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 2: Create HistoryWindow.swift**

```swift
//
//  HistoryWindow.swift
//  pyile_manager
//
//  Full history list with per-entry undo and error reporting
//

import SwiftUI

struct HistoryWindow: View {
    @ObservedObject var fileMonitor: FileMonitorService

    var body: some View {
        Group {
            if fileMonitor.recentEvents.isEmpty {
                Text("No file activity yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(fileMonitor.recentEvents) { entry in
                    EventRow(entry: entry) {
                        Task { await fileMonitor.undo(entry) }
                    }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .navigationTitle("History")
        .alert(
            "Undo Failed",
            isPresented: Binding(
                get: { fileMonitor.undoError != nil },
                set: { if !$0 { fileMonitor.undoError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { fileMonitor.undoError = nil }
        } message: {
            Text(fileMonitor.undoError ?? "")
        }
    }
}
```

- [ ] **Step 3: Add the history Window scene**

In `pyile_managerApp.swift`, after the existing `Window("Settings", id: "settings")` scene block, add:

```swift
        // History Window (shown on demand)
        Window("History", id: "history") {
            HistoryWindow(fileMonitor: fileMonitor)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
```

- [ ] **Step 4: Build and run all tests**

Run: `xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj -scheme pyile_manager -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add pyile_manager_gui/pyile_manager/Views/MenuBarView.swift pyile_manager_gui/pyile_manager/Views/HistoryWindow.swift pyile_manager_gui/pyile_manager/pyile_managerApp.swift
git commit -m "feat: add undo buttons and History window

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 10: End-to-end manual verification

**Files:** none (verification only)

- [ ] **Step 1: Undo a move while monitoring is active**

1. Run the app. Download a file into a watched folder so it gets auto-sorted.
2. Click Undo on the event in the menu bar.
3. Expected: file returns to the watched folder, the row shows strikethrough, and — critically — the file is **NOT re-sorted away** within the next ~5 seconds (the suspend+drain works even though the file still has download metadata).
4. `tail -2 ~/.config/pyile_manager/history.jsonl` — expected: an `{"type":"undo","ref":"<uuid>",...}` line was appended; no lines were rewritten.

- [ ] **Step 2: Undo a move+rename chain**

1. Configure a watched folder that is also in the AI Rename Folders list; drop a PDF so it is moved AND renamed.
2. Undo either event. Expected: both rows strike through, and the file is back at its original path with its original name.

- [ ] **Step 3: Undo refusal paths**

1. Undo a move whose original folder now contains a new file with the same name. Expected: "Undo Failed … another file now exists at …" alert; both files untouched.
2. Trash a duplicate, empty the Trash, then undo the duplicate event. Expected: "the file is no longer at …" alert; no crash.

- [ ] **Step 4: Restart persistence**

Quit and relaunch. Expected: history list intact, undone rows still struck through (the undo records folded correctly), no notifications on load.

---

## Self-review notes (already applied)

- `FileEvent` Codable keeps `id` stable because synthesized decoding bypasses the custom `init` — asserted by `testCodableRoundTripPreservesIdentity`.
- `MoveResult.duplicateRemoved` is renamed in Task 3 and every consumer updated in the same task (single switch in `FileMonitorService`).
- `EventRow` changes shape twice (Task 6: `HistoryEntry`; Task 9: `onUndo`) — each task shows the full struct as it must look at that point, so tasks remain executable in order.
- `chainFor` falls back to `[entry]` when the filtered chain is empty (e.g., undoing from a stale snapshot), so undo never silently no-ops.
- Out-of-scope guards: no redo, no directory auto-creation, no metadata stripping, no tag-sorting, no sandbox work — all deliberately absent.
