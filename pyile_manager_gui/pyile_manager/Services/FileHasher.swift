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
