//
//  MetadataExtractor.swift
//  pyile_manager
//
//  Extracts download source URL from macOS file metadata using Spotlight APIs
//

import Foundation
import CoreServices

struct MetadataExtractor {

    /// Get the download source URL (the page where the file was downloaded from).
    /// Returns the second URL from kMDItemWhereFroms (the viewing page, not the direct download link).
    static func getDownloadSourceURL(for fileURL: URL) -> String? {
        guard let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, fileURL as CFURL) else {
            return nil
        }

        guard let whereFroms = MDItemCopyAttribute(mdItem, kMDItemWhereFroms) as? [String] else {
            return nil
        }

        // Index 0 = direct download URL, Index 1 = viewing page URL
        guard whereFroms.count >= 2 else { return nil }
        return whereFroms[1]
    }

    /// Extract domain name from a URL string.
    /// `loc` specifies which part of the domain to return (e.g., loc=1 returns "github" from "www.github.com").
    static func getDomainName(from urlString: String, loc: Int = 1) -> String? {
        guard let url = URL(string: urlString), let host = url.host else {
            return nil
        }

        let parts = host.split(separator: ".").map(String.init)
        if loc < parts.count {
            return parts[loc]
        }
        return host
    }
}
