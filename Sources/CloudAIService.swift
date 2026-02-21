// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import Foundation
import os

private let logger = Logger(subsystem: "com.writeassist", category: "CloudAIService")

enum AIProvider: String, CaseIterable, Sendable, Codable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case ollama = "Ollama (Local)"
}

enum CloudAIError: Error, LocalizedError {
    case noAPIKey
    case networkUnavailable
    case invalidResponse
    case rateLimited
    case serverError(String)
    case ollamaNotRunning
    case ollamaModelNotFound(String)
    case ollamaNoModelsAvailable
    case ollamaTimeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey:              return "No API key configured"
        case .networkUnavailable:    return "Network unavailable"
        case .invalidResponse:       return "Invalid response from AI service"
        case .rateLimited:           return "Rate limited — please wait"
        case .serverError(let m):    return "Server error: \(m)"
        case .ollamaNotRunning:      return "Ollama is not running. Start it with `ollama serve`."
        case .ollamaModelNotFound(let m): return "Model '\(m)' not found. Run `ollama pull \(m)` to download it."
        case .ollamaNoModelsAvailable: return "No models installed. Run `ollama pull llama3.2` to get started."
        case .ollamaTimeout:         return "Model is taking too long. Try a smaller model or check system resources."
        }
    }
}

protocol AICompletionService: Sendable {
    func complete(prompt: String, systemPrompt: String) async throws -> String
    func chat(messages: [(role: String, content: String)], systemPrompt: String) async throws -> String
}

// MARK: - Cloud AI Service

@MainActor
@Observable
final class CloudAIService: @unchecked Sendable {
    static let shared = CloudAIService()

    var provider: AIProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: "aiProvider")
        }
    }

    var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }

    var ollamaModelName: String {
        didSet { UserDefaults.standard.set(ollamaModelName, forKey: "ollamaModelName") }
    }

    var isConfigured: Bool {
        if provider == .ollama {
            return !ollamaModelName.isEmpty
        }
        return apiKey != nil
    }

    var isProcessing = false

    private var apiKey: String? {
        let keychainKey = provider == .anthropic ? "anthropic_api_key" : "openai_api_key"
        return KeychainHelper.load(key: keychainKey)
    }

    // Rate limiting
    private var lastRequestTime: ContinuousClock.Instant?
    private let minRequestInterval: Duration = .seconds(1)

    private init() {
        let defaults = UserDefaults.standard
        provider = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .anthropic
        ollamaBaseURL = defaults.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        ollamaModelName = defaults.string(forKey: "ollamaModelName") ?? ""
    }

    // MARK: - API Key Management

    func setAPIKey(_ key: String) {
        let keychainKey = provider == .anthropic ? "anthropic_api_key" : "openai_api_key"
        _ = KeychainHelper.save(key: keychainKey, value: key)
    }

    func clearAPIKey() {
        let keychainKey = provider == .anthropic ? "anthropic_api_key" : "openai_api_key"
        KeychainHelper.delete(key: keychainKey)
    }

    func hasAPIKey() -> Bool {
        apiKey != nil
    }

    // MARK: - Connection Test

    func testConnection() async -> Bool {
        do {
            let result = try await complete(prompt: "Say 'ok'", systemPrompt: "Respond with just 'ok'")
            return !result.isEmpty
        } catch {
            logger.warning("Connection test failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Completion

    func complete(prompt: String, systemPrompt: String) async throws -> String {
        // Rate limiting
        if let lastTime = lastRequestTime,
           ContinuousClock.now - lastTime < minRequestInterval {
            try await Task.sleep(for: minRequestInterval)
        }

        isProcessing = true
        defer { isProcessing = false }

        lastRequestTime = .now

        switch provider {
        case .ollama:
            let service = makeOllamaService()
            return try await service.complete(prompt: prompt, systemPrompt: systemPrompt)
        case .anthropic:
            guard let key = apiKey else { throw CloudAIError.noAPIKey }
            return try await callAnthropic(key: key, prompt: prompt, systemPrompt: systemPrompt)
        case .openai:
            guard let key = apiKey else { throw CloudAIError.noAPIKey }
            return try await callOpenAI(key: key, prompt: prompt, systemPrompt: systemPrompt)
        }
    }

    // MARK: - Rewrite

    func rewrite(text: String, style: AIRewriteStyle) async throws -> String {
        let prefs = PreferencesManager.shared
        let (system, user) = AIPromptTemplates.rewritePrompt(
            text: text, style: style,
            formality: prefs.formalityLevel,
            audience: prefs.audienceLevel
        )
        return try await complete(prompt: user, systemPrompt: system)
    }

    // MARK: - Smart Suggestions

    func smartSuggestions(for issue: WritingIssue, context: String) async throws -> [String] {
        let (system, user) = AIPromptTemplates.smartSuggestionPrompt(
            text: context, issueMessage: issue.message
        )
        let result = try await complete(prompt: user, systemPrompt: system)
        return result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Chat

    func chat(messages: [(role: String, content: String)]) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        lastRequestTime = .now

        switch provider {
        case .ollama:
            let service = makeOllamaService()
            return try await service.chat(
                messages: messages,
                systemPrompt: AIPromptTemplates.chatAssistantPrompt()
            )
        case .anthropic:
            guard let key = apiKey else { throw CloudAIError.noAPIKey }
            return try await chatAnthropic(key: key, messages: messages)
        case .openai:
            guard let key = apiKey else { throw CloudAIError.noAPIKey }
            return try await chatOpenAI(key: key, messages: messages)
        }
    }

    // MARK: - Anthropic API

    private func callAnthropic(key: String, prompt: String, systemPrompt: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode == 429 { throw CloudAIError.rateLimited }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.serverError(errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw CloudAIError.invalidResponse
        }

        return text
    }

    private func chatAnthropic(key: String, messages: [(role: String, content: String)]) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let apiMessages = messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 2048,
            "system": AIPromptTemplates.chatAssistantPrompt(),
            "messages": apiMessages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode == 429 { throw CloudAIError.rateLimited }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.serverError(errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw CloudAIError.invalidResponse
        }

        return text
    }

    // MARK: - OpenAI API

    private func callOpenAI(key: String, prompt: String, systemPrompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode == 429 { throw CloudAIError.rateLimited }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.serverError(errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw CloudAIError.invalidResponse
        }

        return text
    }

    // MARK: - Ollama Helpers

    var ollamaBaseURLValue: URL {
        URL(string: ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
    }

    private func makeOllamaService() -> OllamaService {
        OllamaService(baseURL: ollamaBaseURLValue, modelName: ollamaModelName)
    }

    func listOllamaModels() async throws -> [OllamaModel] {
        try await OllamaService.listModels(baseURL: ollamaBaseURLValue)
    }

    func isOllamaReachable() async -> Bool {
        await OllamaService.isServerReachable(baseURL: ollamaBaseURLValue)
    }

    private func chatOpenAI(key: String, messages: [(role: String, content: String)]) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": AIPromptTemplates.chatAssistantPrompt()]
        ]
        apiMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "max_tokens": 2048,
            "messages": apiMessages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode == 429 { throw CloudAIError.rateLimited }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.serverError(errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw CloudAIError.invalidResponse
        }

        return text
    }
}
