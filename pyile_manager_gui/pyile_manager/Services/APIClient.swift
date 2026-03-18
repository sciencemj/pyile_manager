//
//  APIClient.swift
//  pyile_manager
//
//  HTTP API client for backend communication
//

import Foundation

enum APIError: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case httpError(Int)
    case serverError(String)
}

class APIClient {
    private let baseURL = "http://127.0.0.1:8000"
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Private helpers

    private func fetch(_ path: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        return data
    }

    private func send(_ path: String, method: String, body: Data? = nil) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(NSError(domain: "", code: -1))
        }
        guard http.statusCode == 200 else {
            throw APIError.httpError(http.statusCode)
        }
    }

    // MARK: - Public API

    func getConfig() async throws -> AppConfig {
        let data = try await fetch("/api/config")
        do { return try decoder.decode(AppConfig.self, from: data) }
        catch { throw APIError.decodingError(error) }
    }

    func updateConfig(_ config: AppConfig) async throws {
        let body = try encoder.encode(config)
        try await send("/api/config", method: "PUT", body: body)
    }

    func getStatus() async throws -> StatusResponse {
        let data = try await fetch("/api/status")
        do { return try decoder.decode(StatusResponse.self, from: data) }
        catch { throw APIError.decodingError(error) }
    }

    func startMonitoring() async throws {
        try await send("/api/start-monitor", method: "POST")
    }

    func stopMonitoring() async throws {
        try await send("/api/stop-monitor", method: "POST")
    }
}
