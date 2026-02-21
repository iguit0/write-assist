# Design: Ollama & Local Model Support

## Summary

Add Ollama as a third AI provider in WriteAssist, enabling users to run all AI features (rewrite, smart suggestions, chat) against locally-hosted models with no API key required. Uses a protocol-based service layer for clean separation.

## Decisions

- **Provider mode:** Global toggle (one provider at a time: Anthropic, OpenAI, or Ollama)
- **Feature scope:** Full parity — all 3 AI features work with local models
- **Model selection:** Auto-detect installed models via Ollama's `/api/tags` endpoint, shown in a dropdown
- **Server URL:** Configurable with default `http://localhost:11434`
- **Architecture:** Protocol-based — new `OllamaService` conforms to expanded `AICompletionService` protocol

## Data Model

### AIProvider enum (expanded)

```swift
enum AIProvider: String, CaseIterable, Sendable, Codable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case ollama = "Ollama (Local)"
}
```

### OllamaModel

```swift
struct OllamaModel: Identifiable, Codable, Sendable {
    let name: String       // e.g. "llama3.2:latest"
    let size: Int64        // bytes
    let modifiedAt: Date
    var id: String { name }
}
```

### New error cases

```swift
case ollamaNotRunning        // Connection refused
case ollamaModelNotFound     // Selected model not installed
case ollamaNoModelsAvailable // No models installed
case ollamaTimeout           // Inference took too long
```

### Storage

- `ollamaBaseURL` in UserDefaults (default: `http://localhost:11434`)
- `ollamaModelName` in UserDefaults
- No Keychain needed for Ollama

## Architecture

### Protocol expansion

```swift
protocol AICompletionService: Sendable {
    func complete(prompt: String, systemPrompt: String) async throws -> String
    func chat(messages: [(role: String, content: String)], systemPrompt: String) async throws -> String
}
```

### OllamaService (new file)

```swift
struct OllamaService: AICompletionService {
    let baseURL: URL
    let modelName: String

    func complete(prompt: String, systemPrompt: String) async throws -> String
    func chat(messages: [(role: String, content: String)], systemPrompt: String) async throws -> String

    static func listModels(baseURL: URL) async throws -> [OllamaModel]
    static func isServerReachable(baseURL: URL) async -> Bool
}
```

- Uses Ollama's `/api/chat` endpoint for both single-turn and multi-turn
- `Sendable` naturally (struct with `URL` and `String` properties)
- Uses `Codable` structs for response parsing (not manual `JSONSerialization`)
- `nonisolated` — pure network calls, no `@MainActor` state

### CloudAIService changes

- Add `ollamaBaseURL: String` and `ollamaModelName: String` observable properties
- `isConfigured` returns server reachability for Ollama (not API key check)
- `complete()` and `chat()` delegate to `OllamaService` when `provider == .ollama`
- New `listOllamaModels()` and `testOllamaConnection()` methods

### Unchanged files

- `AIPromptTemplates.swift` — same prompts work for local models
- `DocumentViewModel.swift` — calls `CloudAIService` which handles routing
- `PreferencesManager.swift` — no Ollama-specific preferences needed
- `KeychainHelper.swift` — Ollama doesn't use API keys

## Error Handling

| Scenario | Detection | User message |
|----------|-----------|--------------|
| Ollama not running | `URLError.cannotConnectToHost` | "Ollama is not running. Start it with `ollama serve`." |
| Model not found | HTTP 404 from Ollama | "Model 'X' not found. Run `ollama pull X` to download it." |
| No models installed | Empty response from `/api/tags` | "No models installed. Run `ollama pull llama3.2` to get started." |
| Inference timeout | 60s URLSession timeout | "Model is taking too long. Try a smaller model or check system resources." |
| Server goes down mid-conversation | Per-request error handling | Error shown inline in chat, user can retry |
| Model deleted after selection | `listModels()` refreshes on settings open | Warning shown, prompt re-selection |
| Empty response content | Check for empty string | Treated as `invalidResponse` |
| Invalid base URL | URL validation on input | "Invalid server URL format" |

## Settings UI

### Provider picker

3-segment control: Anthropic | OpenAI | Ollama

### Conditional sections

When `provider == .ollama`:
- **Server URL** — text field, default `http://localhost:11434`
- **Connection status** — green/red dot with label, checked on panel open
- **Model picker** — dropdown from `listModels()`, shows name + size
- **Refresh button** — re-fetches model list
- **Test button** — sends quick prompt to verify model works

When `provider != .ollama`:
- **API Key** — secure text field (existing behavior)
- **Test button** — existing cloud connection test

### AIChatPanel empty state

For Ollama: "Ollama is not running" or "No model selected" with instructions, instead of "Add your API key".

## Performance

- All HTTP calls via `async/await` (no main thread blocking)
- Model list cached in memory, refreshed on settings open
- 60s timeout for inference, 5s for health checks and model listing
- Existing 1s rate limit reused (prevents Ollama queue buildup)
- `num_predict` parameter caps output: 1024 (complete), 2048 (chat)

## Files Changed

| File | Change type |
|------|-------------|
| `Sources/OllamaService.swift` | New file |
| `Sources/CloudAIService.swift` | Modified — add `.ollama` provider, Ollama properties, delegation |
| `Sources/ContentView.swift` | Modified — `SettingsPanel` Ollama UI, `AIChatPanel` empty state |
