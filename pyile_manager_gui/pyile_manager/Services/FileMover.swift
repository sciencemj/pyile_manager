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
