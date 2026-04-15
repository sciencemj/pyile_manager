//
//  ContentExtractor.swift
//  pyile_manager
//
//  File content extraction utilities for PDF, PPTX, and text files
//

import Foundation
import PDFKit

enum FileType {
    case image, pdf, pptx, text, unknown
}

struct ContentExtractor {

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "webp", "tiff"]
    private static let pptxExtensions: Set<String> = ["ppt", "pptx"]

    static func getFileType(_ url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if pptxExtensions.contains(ext) { return .pptx }
        if ext == "txt" { return .text }
        return .unknown
    }

    // MARK: - PDF

    static func extractTextFromPDF(at url: URL) -> String? {
        guard let document = PDFDocument(url: url) else {
            print("Failed to open PDF: \(url.lastPathComponent)")
            return nil
        }

        var textContent: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                textContent.append(text)
            }
        }

        let fullText = textContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // If text is too short, it's likely a scanned PDF
        if fullText.count < 50 { return nil }
        return fullText
    }

    // MARK: - PPTX

    static func extractTextFromPPTX(at url: URL) -> String? {
        // PPTX is a ZIP archive — use unzip to extract slide XML files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Unzip the pptx
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", "-q", url.path, "ppt/slides/slide*.xml", "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                print("Failed to unzip PPTX: exit code \(process.terminationStatus)")
                return nil
            }

            // Find and parse slide XML files
            let slidesDir = tempDir.appendingPathComponent("ppt/slides")
            guard let slideFiles = try? FileManager.default.contentsOfDirectory(at: slidesDir, includingPropertiesForKeys: nil)
                .filter({ $0.pathExtension == "xml" })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            else { return nil }

            var allText: [String] = []
            for slideFile in slideFiles {
                if let xmlData = try? Data(contentsOf: slideFile) {
                    let parser = PPTXTextParser(data: xmlData)
                    allText.append(contentsOf: parser.parse())
                }
            }

            let result = allText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result

        } catch {
            print("Error extracting PPTX text: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Text

    static func extractTextFromTXT(at url: URL) -> String? {
        // Try UTF-8 first, fallback to latin1
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        print("Error reading text file: \(url.lastPathComponent)")
        return nil
    }
}

// MARK: - PPTX XML Parser

/// Parses PPTX slide XML to extract text from <a:t> elements
private class PPTXTextParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var texts: [String] = []
    private var currentText = ""
    private var insideTextElement = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> [String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return texts
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        // Match <a:t> elements (text runs in OOXML)
        if elementName == "a:t" || elementName.hasSuffix(":t") {
            insideTextElement = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideTextElement {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "a:t" || elementName.hasSuffix(":t") {
            insideTextElement = false
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                texts.append(trimmed)
            }
        }
    }
}
