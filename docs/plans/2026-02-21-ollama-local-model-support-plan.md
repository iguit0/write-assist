# Ollama Local Model Support — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Ollama as a third AI provider so users can run all AI features (rewrite, smart suggestions, chat) against locally-hosted models with no API key.

**Architecture:** Protocol-based service layer. A new `OllamaService` struct conforms to an expanded `AICompletionService` protocol. `CloudAIService` delegates to it when `provider == .ollama`. The Settings UI conditionally shows Ollama-specific controls (server URL, model picker) instead of an API key field.

**Tech Stack:** Swift 6, SwiftUI, macOS 15+, SPM, URLSession (async/await), Codable for Ollama JSON responses

**Design doc:** `docs/plans/2026-02-21-ollama-local-model-support-design.md`

**Quality gates (run after every task):**
```bash
cd "/Users/igoralves/Documents/Side Projects/WriteAssist" && swift build 2>&1 | tail -5
```

---

### Task 1: Create OllamaService with Codable types and core networking

**Files:**
- Create: `Sources/OllamaService.swift`

This task creates the entire `OllamaService.swift` file: the `OllamaModel` type, Codable response structs for Ollama's JSON API, and the `OllamaService` struct with `complete`, `chat`, `listModels`, and `isServerReachable` methods.

**Step 1: Create `Sources/OllamaService.swift` with the complete implementation**

```swift
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
```

**Step 2: Verify it compiles (it won't yet — depends on Task 2 for error cases)**

This file references `CloudAIError.ollamaNotRunning`, `.ollamaModelNotFound`, `.ollamaNoModelsAvailable`, and `.ollamaTimeout` which don't exist yet. That's fine — they're added in Task 2. File creation is complete.

**Step 3: Commit**

```bash
git add Sources/OllamaService.swift
git commit -m "feat: add OllamaService with Codable types and core networking"
```

---

### Task 2: Expand CloudAIService — provider enum, error cases, Ollama delegation

**Files:**
- Modify: `Sources/CloudAIService.swift` (lines 9-12 for AIProvider, lines 14-30 for errors, lines 32-34 for protocol, lines 43-51 for properties, lines 64-66 for init, lines 98-118 for complete, lines 146-160 for chat, plus new methods)

This task modifies `CloudAIService.swift` to:
1. Add `.ollama` to `AIProvider`
2. Add Ollama-specific error cases to `CloudAIError`
3. Add `chat(messages:systemPrompt:)` to the `AICompletionService` protocol
4. Add `ollamaBaseURL` and `ollamaModelName` observable properties
5. Update `isConfigured` to handle Ollama (checks that model name is set, not API key)
6. Update `complete()` and `chat()` to delegate to `OllamaService` when provider is `.ollama`
7. Add `listOllamaModels()` and `ollamaBaseURLValue` helper

**Step 1: Add `.ollama` to `AIProvider` enum**

In `Sources/CloudAIService.swift`, replace lines 9-12:

```swift
enum AIProvider: String, CaseIterable, Sendable, Codable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
}
```

with:

```swift
enum AIProvider: String, CaseIterable, Sendable, Codable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case ollama = "Ollama (Local)"
}
```

**Step 2: Add Ollama error cases to `CloudAIError`**

Replace lines 14-30:

```swift
enum CloudAIError: Error, LocalizedError {
    case noAPIKey
    case networkUnavailable
    case invalidResponse
    case rateLimited
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:           return "No API key configured"
        case .networkUnavailable: return "Network unavailable"
        case .invalidResponse:    return "Invalid response from AI service"
        case .rateLimited:        return "Rate limited — please wait"
        case .serverError(let m): return "Server error: \(m)"
        }
    }
}
```

with:

```swift
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
```

**Step 3: Expand `AICompletionService` protocol**

Replace lines 32-34:

```swift
protocol AICompletionService: Sendable {
    func complete(prompt: String, systemPrompt: String) async throws -> String
}
```

with:

```swift
protocol AICompletionService: Sendable {
    func complete(prompt: String, systemPrompt: String) async throws -> String
    func chat(messages: [(role: String, content: String)], systemPrompt: String) async throws -> String
}
```

**Step 4: Add Ollama properties and update `isConfigured`**

After the existing `provider` property (after line 47), add:

```swift
    var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }

    var ollamaModelName: String {
        didSet { UserDefaults.standard.set(ollamaModelName, forKey: "ollamaModelName") }
    }
```

Replace the `isConfigured` computed property (lines 49-51):

```swift
    var isConfigured: Bool {
        apiKey != nil
    }
```

with:

```swift
    var isConfigured: Bool {
        if provider == .ollama {
            return !ollamaModelName.isEmpty
        }
        return apiKey != nil
    }
```

**Step 5: Update `init()` to load Ollama settings**

Replace lines 64-66:

```swift
    private init() {
        provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .anthropic
    }
```

with:

```swift
    private init() {
        let defaults = UserDefaults.standard
        provider = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .anthropic
        ollamaBaseURL = defaults.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        ollamaModelName = defaults.string(forKey: "ollamaModelName") ?? ""
    }
```

**Step 6: Update `complete()` to handle Ollama**

Replace the `complete` method (lines 98-118):

```swift
    func complete(prompt: String, systemPrompt: String) async throws -> String {
        guard let key = apiKey else { throw CloudAIError.noAPIKey }

        // Rate limiting
        if let lastTime = lastRequestTime,
           ContinuousClock.now - lastTime < minRequestInterval {
            try await Task.sleep(for: minRequestInterval)
        }

        isProcessing = true
        defer { isProcessing = false }

        lastRequestTime = .now

        switch provider {
        case .anthropic:
            return try await callAnthropic(key: key, prompt: prompt, systemPrompt: systemPrompt)
        case .openai:
            return try await callOpenAI(key: key, prompt: prompt, systemPrompt: systemPrompt)
        }
    }
```

with:

```swift
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
```

**Step 7: Update `chat()` to handle Ollama**

Replace the `chat` method (lines 146-160):

```swift
    func chat(messages: [(role: String, content: String)]) async throws -> String {
        guard let key = apiKey else { throw CloudAIError.noAPIKey }

        isProcessing = true
        defer { isProcessing = false }

        lastRequestTime = .now

        switch provider {
        case .anthropic:
            return try await chatAnthropic(key: key, messages: messages)
        case .openai:
            return try await chatOpenAI(key: key, messages: messages)
        }
    }
```

with:

```swift
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
```

**Step 8: Add Ollama helper methods at the end of the class (before the closing `}`)**

Add these methods before the final `}` of `CloudAIService`:

```swift
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
```

**Step 9: Build and verify**

```bash
cd "/Users/igoralves/Documents/Side Projects/WriteAssist" && swift build 2>&1 | tail -5
```

Expected: `Build complete!` (or may show warnings, but no errors)

**Step 10: Commit**

```bash
git add Sources/CloudAIService.swift
git commit -m "feat: expand CloudAIService with Ollama provider, error cases, and delegation"
```

---

### Task 3: Update SettingsPanel for Ollama-specific controls

**Files:**
- Modify: `Sources/ContentView.swift` (the `SettingsPanel` struct, lines 781-965)

This task replaces the hardcoded API key section in `SettingsPanel` with conditional UI: cloud providers show the API key field, Ollama shows server URL, connection status, model picker, and refresh.

**Step 1: Add Ollama state variables to SettingsPanel**

In `Sources/ContentView.swift`, replace lines 781-787:

```swift
struct SettingsPanel: View {
    @State private var prefs = PreferencesManager.shared
    @State private var aiService = CloudAIService.shared
    @State private var isRuleTogglesExpanded = false
    @State private var apiKeyInput = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?
```

with:

```swift
struct SettingsPanel: View {
    @State private var prefs = PreferencesManager.shared
    @State private var aiService = CloudAIService.shared
    @State private var isRuleTogglesExpanded = false
    @State private var apiKeyInput = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?
    // Ollama state
    @State private var ollamaModels: [OllamaModel] = []
    @State private var isLoadingModels = false
    @State private var ollamaReachable: Bool?
```

**Step 2: Replace the AI Provider settings section**

Replace the AI Provider `settingsSection` block (lines 793-856) — everything from `settingsSection(title: "AI Provider"` through the closing `}` of that section — with this conditional implementation:

```swift
                // AI Provider
                settingsSection(title: "AI Provider", icon: "sparkles") {
                    Picker("Provider", selection: $aiService.provider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: aiService.provider) {
                        connectionTestResult = nil
                        if aiService.provider == .ollama {
                            checkOllamaStatus()
                        }
                    }

                    if aiService.provider == .ollama {
                        ollamaSettingsContent
                    } else {
                        cloudSettingsContent
                    }
                }
```

**Step 3: Add the `ollamaSettingsContent` computed property**

Add this below the `ruleToggleRow` method (after line 964), before the closing `}` of `SettingsPanel`:

```swift
    // MARK: - Ollama Settings

    private var ollamaSettingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Server URL
            HStack(spacing: 6) {
                TextField("Server URL", text: $aiService.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { checkOllamaStatus() }

                Button {
                    checkOllamaStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Connection status
            HStack(spacing: 8) {
                if let reachable = ollamaReachable {
                    Circle()
                        .fill(reachable ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(reachable ? "Connected" : "Not running")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Checking...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Model picker
            if ollamaReachable == true {
                HStack(spacing: 6) {
                    Picker("Model", selection: $aiService.ollamaModelName) {
                        if aiService.ollamaModelName.isEmpty {
                            Text("Select a model").tag("")
                        }
                        ForEach(ollamaModels) { model in
                            Text("\(model.name) (\(model.formattedSize))").tag(model.name)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 11))

                    if isLoadingModels {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button {
                            loadOllamaModels()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Test button
                if !aiService.ollamaModelName.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            isTestingConnection = true
                            connectionTestResult = nil
                            Task {
                                let result = await aiService.testConnection()
                                isTestingConnection = false
                                connectionTestResult = result
                            }
                        } label: {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Text("Test Model")
                                    .font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        if let result = connectionTestResult {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result ? .green : .red)
                                .font(.system(size: 12))
                        }

                        Spacer()
                    }
                }
            } else if ollamaReachable == false {
                Text("Start Ollama to select a model: `ollama serve`")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { checkOllamaStatus() }
    }

    private var cloudSettingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SecureField("API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                Button {
                    aiService.setAPIKey(apiKeyInput)
                    apiKeyInput = ""
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(apiKeyInput.isEmpty)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(aiService.hasAPIKey() ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(aiService.hasAPIKey() ? "API key configured" : "No API key")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                if aiService.hasAPIKey() {
                    Button {
                        isTestingConnection = true
                        connectionTestResult = nil
                        Task {
                            let result = await aiService.testConnection()
                            isTestingConnection = false
                            connectionTestResult = result
                        }
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text("Test")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    if let result = connectionTestResult {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result ? .green : .red)
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }

    // MARK: - Ollama Helpers

    private func checkOllamaStatus() {
        ollamaReachable = nil
        Task {
            let reachable = await aiService.isOllamaReachable()
            ollamaReachable = reachable
            if reachable {
                loadOllamaModels()
            }
        }
    }

    private func loadOllamaModels() {
        isLoadingModels = true
        Task {
            do {
                ollamaModels = try await aiService.listOllamaModels()
                // If current model name is empty or not in list, select the first one
                if !ollamaModels.contains(where: { $0.name == aiService.ollamaModelName }),
                   let first = ollamaModels.first {
                    aiService.ollamaModelName = first.name
                }
            } catch {
                ollamaModels = []
            }
            isLoadingModels = false
        }
    }
```

**Step 4: Build and verify**

```bash
cd "/Users/igoralves/Documents/Side Projects/WriteAssist" && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 5: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "feat: add Ollama settings UI with server URL, model picker, and connection status"
```

---

### Task 4: Update AIChatPanel empty state for Ollama

**Files:**
- Modify: `Sources/ContentView.swift` (the `AIChatPanel` struct, lines 1296-1480)

This task updates the "AI Not Configured" view in `AIChatPanel` to show Ollama-specific guidance instead of "Add your API key" when the Ollama provider is selected.

**Step 1: Replace `aiNotConfiguredView`**

Replace lines 1313-1330:

```swift
    private var aiNotConfiguredView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 20)
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.indigo)
            Text("AI Not Configured")
                .font(.system(size: 13, weight: .semibold))
            Text("Add your API key in Settings to use AI features like rewrites, suggestions, and chat.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
```

with:

```swift
    private var aiNotConfiguredView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 20)
            Image(systemName: aiService.provider == .ollama ? "desktopcomputer" : "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(aiService.provider == .ollama ? .orange : .indigo)
            Text(aiService.provider == .ollama ? "Ollama Not Ready" : "AI Not Configured")
                .font(.system(size: 13, weight: .semibold))
            Text(aiService.provider == .ollama
                 ? "Select a model in Settings. Make sure Ollama is running (`ollama serve`)."
                 : "Add your API key in Settings to use AI features like rewrites, suggestions, and chat.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
```

**Step 2: Build and verify**

```bash
cd "/Users/igoralves/Documents/Side Projects/WriteAssist" && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

**Step 3: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "feat: update AIChatPanel empty state with Ollama-specific guidance"
```

---

### Task 5: Final build verification and integration commit

**Files:**
- All modified files from Tasks 1-4

This task does a final clean build, verifies all files are consistent, and ensures the full feature is integrated.

**Step 1: Clean build**

```bash
cd "/Users/igoralves/Documents/Side Projects/WriteAssist" && swift package clean && swift build 2>&1 | tail -20
```

Expected: `Build complete!` with no errors.

**Step 2: Run swiftlint (if any issues, fix them)**

```bash
cd "/Users/igoralves/Documents/Side Projects/WriteAssist" && swiftlint 2>&1 | tail -20
```

Fix any violations that appear in `OllamaService.swift` or in modified sections of `CloudAIService.swift` / `ContentView.swift`.

**Step 3: Verify git status is clean**

```bash
cd "/Users/igoralves/Documents/Side Projects/WriteAssist" && git status
```

All Ollama-related changes should be committed. If any fixes were needed from Step 2, commit them:

```bash
git add -A && git commit -m "fix: resolve swiftlint violations in Ollama integration"
```

---

## Summary of All Changes

| File | What changed |
|------|-------------|
| `Sources/OllamaService.swift` | **New.** `OllamaModel`, Codable response types, `OllamaService` struct with `complete`, `chat`, `listModels`, `isServerReachable` |
| `Sources/CloudAIService.swift` | **Modified.** `.ollama` added to `AIProvider`, 4 new `CloudAIError` cases, protocol expanded with `chat(messages:systemPrompt:)`, Ollama properties (`ollamaBaseURL`, `ollamaModelName`), `isConfigured` updated, `complete()` and `chat()` delegate to `OllamaService`, helper methods added |
| `Sources/ContentView.swift` | **Modified.** `SettingsPanel` shows Ollama-specific UI (server URL, connection status, model picker) conditionally. `AIChatPanel` empty state shows Ollama guidance |

## Unchanged files (confirmed no modifications needed)

- `AIPromptTemplates.swift` — prompts work identically for local models
- `DocumentViewModel.swift` — calls through `CloudAIService` which handles routing
- `PreferencesManager.swift` — no Ollama-specific preferences
- `KeychainHelper.swift` — Ollama doesn't use API keys
- `WriteAssistApp.swift` — no changes needed
- `Package.swift` — no new dependencies
