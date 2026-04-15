//
//  FileMover.swift
//  pyile_manager
//
//  File moving with duplicate detection and configurable behavior
//

import Foundation

struct FileMover {

    enum MoveResult {
        case moved(URL)         // Successfully moved, new URL
        case duplicateRemoved   // Source deleted because duplicate existed
        case duplicateSkipped   // Skipped because duplicate existed and removal disabled
        case failed(String)     // Error message
    }

    /// Move a file to a destination directory.
    /// Handles duplicate detection based on the `removeDuplicate` setting.
    static func moveFile(at source: URL, to destinationDir: URL, removeDuplicate: Bool) -> MoveResult {
        let fm = FileManager.default
        let filename = source.lastPathComponent
        let destPath = destinationDir.appendingPathComponent(filename)

        // Create destination directory if needed
        do {
            try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        } catch {
            return .failed("Failed to create directory: \(error.localizedDescription)")
        }

        // Handle duplicate files
        if fm.fileExists(atPath: destPath.path) {
            print("File already exists: \(destPath.path)")
            if removeDuplicate {
                do {
                    try fm.removeItem(at: source)
                    print("Duplicate file removed: \(filename)")
                    return .duplicateRemoved
                } catch {
                    return .failed("Failed to remove duplicate: \(error.localizedDescription)")
                }
            }
            return .duplicateSkipped
        }

        // Move file
        do {
            try fm.moveItem(at: source, to: destPath)
            print("File moved: \(filename) -> \(destinationDir.path)")
            return .moved(destPath)
        } catch {
            return .failed("Failed to move file: \(error.localizedDescription)")
        }
    }
}
