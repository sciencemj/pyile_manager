//
//  OllamaService.swift
//  pyile_manager
//
//  Direct HTTP integration with Ollama REST API for AI-powered file renaming
//

import Foundation

class OllamaService {
    private let baseURL = "http://localhost:11434"
    var renameModel: String
    var ocrModel: String

    init(renameModel: String = "gemma3:4b", ocrModel: String = "deepocr") {
        self.renameModel = renameModel
        self.ocrModel = ocrModel
    }

    // MARK: - Public API

    /// Main entry point: rename any supported file type using AI.
    /// Returns the new filename (without extension) or nil if renaming fails.
    func renameFileWithAI(at fileURL: URL) async -> String? {
        let fileType = ContentExtractor.getFileType(fileURL)
        var result: OllamaRenameResponse?

        switch fileType {
        case .image:
            result = await renameImageDirectly(at: fileURL)
        case .pdf:
            result = await renamePDFWithOCR(at: fileURL)
        case .pptx:
            if let text = ContentExtractor.extractTextFromPPTX(at: fileURL) {
                result = await renameWithTextContent(text, fileType: "PowerPoint")
            }
        case .text:
            if let text = ContentExtractor.extractTextFromTXT(at: fileURL) {
                result = await renameWithTextContent(text, fileType: "text file")
            }
        case .unknown:
            print("Unsupported file type: \(fileURL.pathExtension)")
            return nil
        }

        guard let name = result?.name else { return nil }
        return OllamaService.sanitizeFilename(name)
    }

    /// Rename the actual file on disk. Preserves the file extension.
    /// Appends timestamp on collision.
    static func renameFileOnDisk(at fileURL: URL, newName: String) -> URL? {
        let ext = fileURL.pathExtension
        let directory = fileURL.deletingLastPathComponent()
        var newFilename = ext.isEmpty ? newName : "\(newName).\(ext)"
        var newURL = directory.appendingPathComponent(newFilename)

        // Handle collision
        if FileManager.default.fileExists(atPath: newURL.path) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            newFilename = ext.isEmpty ? "\(newName)-\(timestamp)" : "\(newName)-\(timestamp).\(ext)"
            newURL = directory.appendingPathComponent(newFilename)
        }

        do {
            try FileManager.default.moveItem(at: fileURL, to: newURL)
            print("Renamed: \(fileURL.lastPathComponent) -> \(newFilename)")
            return newURL
        } catch {
            print("Error renaming file on disk: \(error.localizedDescription)")
            return nil
        }
    }

    /// Sanitize filename: lowercase, underscores only, max 80 chars.
    static func sanitizeFilename(_ name: String) -> String {
        var sanitized = name.map { c -> Character in
            if c.isLetter || c.isNumber || c == "_" { return c }
            return "_"
        }
        var result = String(sanitized)

        // Collapse multiple underscores
        while result.contains("__") {
            result = result.replacingOccurrences(of: "__", with: "_")
        }

        // Strip leading/trailing underscores and lowercase
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "_")).lowercased()

        // Limit length
        if result.count > 80 {
            result = String(result.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        }

        return result
    }

    // MARK: - Private Methods

    private func renameWithTextContent(_ content: String, fileType: String) async -> OllamaRenameResponse? {
        let prompt = generateRenamePrompt(content: content, fileType: fileType)
        return await chatWithFormat(model: renameModel, prompt: prompt, images: nil)
    }

    private func renameImageDirectly(at imageURL: URL) async -> OllamaRenameResponse? {
        guard let imageData = try? Data(contentsOf: imageURL) else {
            print("Failed to read image: \(imageURL.lastPathComponent)")
            return nil
        }
        let base64Image = imageData.base64EncodedString()

        let prompt = """
        Describe this image and generate a descriptive filename.

        Rules:
        - Use lowercase letters and underscores only (e.g., 'my_file_name')
        - Be descriptive and capture the main subject/scene
        - If there's text with numbering in the image, include that number at the start
        - Be concise (under 80 characters)
        - Format: {number}_{descriptive_name} if numbering exists, otherwise just {descriptive_name}
        - Do NOT include file extension
        - Do NOT include date/time

        Examples:
        - Photo of Golden Gate Bridge at sunset → "golden_gate_bridge_sunset"
        - Screenshot of Lecture 3 slide → "3_lecture_programming"
        - Diagram showing network architecture → "network_architecture_diagram"

        Generate only the filename, nothing else.
        """

        return await chatWithFormat(model: renameModel, prompt: prompt, images: [base64Image])
    }

    private func renamePDFWithOCR(at pdfURL: URL) async -> OllamaRenameResponse? {
        // Try text extraction first
        if let textContent = ContentExtractor.extractTextFromPDF(at: pdfURL) {
            return await renameWithTextContent(textContent, fileType: "PDF")
        }

        // Fallback: use OCR model
        guard let pdfData = try? Data(contentsOf: pdfURL) else {
            print("Failed to read PDF for OCR: \(pdfURL.lastPathComponent)")
            return nil
        }
        let base64PDF = pdfData.base64EncodedString()

        // First extract text via OCR
        let ocrText = await chatPlain(
            model: ocrModel,
            prompt: "Extract all text from this PDF document. Return only the extracted text.",
            images: [base64PDF]
        )

        guard let text = ocrText, !text.isEmpty else {
            print("No text extracted from PDF via OCR")
            return nil
        }

        return await renameWithTextContent(text, fileType: "PDF")
    }

    private func generateRenamePrompt(content: String, fileType: String) -> String {
        let truncated = String(content.prefix(2000))
        return """
        Based on the following \(fileType) content, generate a descriptive and concise filename.

        Rules:
        - Use lowercase letters and underscores only (e.g., 'my_file_name')
        - If content contains numbering/sequence (like Lecture 3, Chapter 2, etc.), start with that number
        - Be descriptive but concise (under 80 characters)
        - Capture the main topic or purpose
        - Format: {number}_{descriptive_name} if numbering exists, otherwise just {descriptive_name}
        - Do NOT include file extension
        - Do NOT include date/time

        Examples:
        - Lecture 3 about Programming → "3_programming_lecture"
        - Quarterly Sales Report Q4 → "q4_quarterly_sales_report"
        - Golden Gate Bridge photo → "golden_gate_bridge_sunset"

        Content:
        \(truncated)

        Generate only the filename, nothing else.
        """
    }

    // MARK: - Ollama HTTP API

    /// Call Ollama chat API with structured JSON output format.
    private func chatWithFormat(model: String, prompt: String, images: [String]?) async -> OllamaRenameResponse? {
        var message: [String: Any] = ["role": "user", "content": prompt]
        if let images { message["images"] = images }

        let body: [String: Any] = [
            "model": model,
            "messages": [message],
            "format": [
                "type": "object",
                "properties": ["name": ["type": "string"]],
                "required": ["name"]
            ],
            "stream": false
        ]

        guard let responseData = await performRequest(body: body) else { return nil }

        // Parse response: {"message": {"content": "{\"name\": \"...\"}"}}
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let messageObj = json["message"] as? [String: Any],
              let content = messageObj["content"] as? String,
              let contentData = content.data(using: .utf8)
        else {
            print("Failed to parse Ollama response")
            return nil
        }

        return try? JSONDecoder().decode(OllamaRenameResponse.self, from: contentData)
    }

    /// Call Ollama chat API and return plain text response.
    private func chatPlain(model: String, prompt: String, images: [String]?) async -> String? {
        var message: [String: Any] = ["role": "user", "content": prompt]
        if let images { message["images"] = images }

        let body: [String: Any] = [
            "model": model,
            "messages": [message],
            "stream": false
        ]

        guard let responseData = await performRequest(body: body) else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let messageObj = json["message"] as? [String: Any],
              let content = messageObj["content"] as? String
        else { return nil }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Perform HTTP POST to Ollama API.
    private func performRequest(body: [String: Any]) async -> Data? {
        guard let url = URL(string: "\(baseURL)/api/chat") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // AI inference can be slow

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("Ollama API error: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            return data
        } catch {
            print("Ollama API request failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Response Model

struct OllamaRenameResponse: Codable {
    let name: String
}
