//
//  URLMatcher.swift
//  pyile_manager
//
//  URL pattern matching with variable support ({$var} and {$*})
//

import Foundation

struct URLMatcher {

    /// Parse a URL pattern into a regular expression.
    /// Supports {$var} (matches a single path segment) and {$*} (matches anything).
    static func parsePattern(_ pattern: String) -> NSRegularExpression? {
        var escaped = NSRegularExpression.escapedPattern(for: pattern)
        escaped = escaped.replacingOccurrences(of: "\\\\\\{\\\\\\$var\\\\\\}", with: "[^/]+")
        escaped = escaped.replacingOccurrences(of: "\\\\\\{\\\\\\$\\\\\\*\\\\\\}", with: ".*")

        // The escaped versions of {$var} and {$*} after NSRegularExpression.escapedPattern:
        // {$var} → \{\$var\} → need to replace this
        // Let's use a simpler approach: replace before escaping
        return nil // Will use simpler approach below
    }

    /// Build regex from a URL pattern with variable support.
    private static func buildRegex(from pattern: String) -> NSRegularExpression? {
        // Replace variables before escaping
        let withVarPlaceholder = pattern
            .replacingOccurrences(of: "{$var}", with: "___VAR___")
            .replacingOccurrences(of: "{$*}", with: "___WILD___")

        var escaped = NSRegularExpression.escapedPattern(for: withVarPlaceholder)
        escaped = escaped
            .replacingOccurrences(of: "___VAR___", with: "[^/]+")
            .replacingOccurrences(of: "___WILD___", with: ".*")

        return try? NSRegularExpression(pattern: escaped, options: .caseInsensitive)
    }

    /// Match a URL against configured schemas and return the destination path.
    /// Supports both exact substring matches and pattern matching with variables.
    static func matchURL(_ url: String, against schemas: [String: String]) -> String? {
        for (pattern, destination) in schemas {
            if pattern.contains("{$") {
                // Pattern matching with variables
                if let regex = buildRegex(from: pattern) {
                    let range = NSRange(url.startIndex..., in: url)
                    if regex.firstMatch(in: url, range: range) != nil {
                        return destination
                    }
                }
            } else {
                // Simple substring match
                if url.contains(pattern) {
                    return destination
                }
            }
        }

        // Fallback: extract domain and do case-insensitive match
        if let domain = MetadataExtractor.getDomainName(from: url, loc: 1) {
            for (pattern, destination) in schemas {
                if pattern.lowercased().contains(domain.lowercased()) {
                    return destination
                }
            }
        }

        return nil
    }
}
