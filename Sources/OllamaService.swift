// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import os

private let logger = Logger(subsystem: "com.writeassist", category: "OllamaService")

// MARK: - Ollama Model

struct OllamaModel: Identifiable, Sendable {
    let name: String
    let size: Int64
    let modifiedAt: Date
    var id: String { name }

    var formattedSize: String {
        let gb = Double(size) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(size) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Ollama API Response Types

/// Response from `GET /api/tags` — lists installed models.
private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModelEntry]
}

private struct OllamaModelEntry: Decodable {
    let name: String
    let size: Int64
    let modified_at: String // ISO 8601
}

/// Response from `POST /api/chat` — chat completion.
private struct OllamaChatResponse: Decodable {
    let message: OllamaChatMessage
}

private struct OllamaChatMessage: Decodable {
    let role: String
    let content: String
}

// MARK: - Ollama Service

struct OllamaService: Sendable {
    let baseURL: URL
    let modelName: String

    /// URLSession with 60s timeout for inference requests.
    private static let inferenceSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    /// URLSession with 5s timeout for health checks and model listing.
    private static let quickSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    // MARK: - Completion (single-turn)

    func complete(prompt: String, systemPrompt: String) async throws -> String {
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt]
        ]
        return try await sendChat(messages: messages, numPredict: 1024)
    }

    // MARK: - Chat (multi-turn)

    func chat(messages: [(role: String, content: String)], systemPrompt: String) async throws -> String {
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })
        return try await sendChat(messages: apiMessages, numPredict: 2048)
    }

    // MARK: - Model Discovery

    static func listModels(baseURL: URL) async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await performRequest(request, session: quickSession, baseURL: baseURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudAIError.invalidResponse
        }

        let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)

        if tagsResponse.models.isEmpty {
            throw CloudAIError.ollamaNoModelsAvailable
        }

        let iso8601 = ISO8601DateFormatter()
        // Some Ollama versions include fractional seconds — add the option.
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return tagsResponse.models.map { entry in
            let date = iso8601.date(from: entry.modified_at) ?? .now
            return OllamaModel(name: entry.name, size: entry.size, modifiedAt: date)
        }
    }

    static func isServerReachable(baseURL: URL) async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await quickSession.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    private func sendChat(messages: [[String: String]], numPredict: Int) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "stream": false,
            "options": ["num_predict": numPredict]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.performRequest(request, session: Self.inferenceSession, baseURL: baseURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw CloudAIError.ollamaModelNotFound(modelName)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.serverError(errorBody)
        }

        let chatResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let content = chatResponse.message.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw CloudAIError.invalidResponse
        }

        return content
    }

    /// Wraps URLSession.data(for:) to catch connection errors and map them
    /// to domain-specific CloudAIError cases.
    private static func performRequest(
        _ request: URLRequest,
        session: URLSession,
        baseURL: URL
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                logger.warning("Ollama server not reachable at \(baseURL.absoluteString)")
                throw CloudAIError.ollamaNotRunning
            case .timedOut:
                logger.warning("Ollama request timed out")
                throw CloudAIError.ollamaTimeout
            default:
                throw urlError
            }
        }
    }
}
