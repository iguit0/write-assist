# Ollama base URL not validated as loopback — SSRF risk

**Labels:** `security` `P1-high`  
**Status:** 🆕 New

## Description

The Ollama base URL is read from `UserDefaults` and accepted without validation. A maliciously crafted configuration (or a preferences file tampered with by another process) could set the URL to an arbitrary remote host. Every text the user types would then be silently forwarded to an attacker's server using the full Ollama API format.

```swift
// CloudAIService.swift — no validation before use
let ollamaBaseURL = PreferencesManager.shared.ollamaBaseURL
let url = URL(string: "\(ollamaBaseURL)/api/generate")!
```

## Affected Files

- `Sources/CloudAIService.swift` — Ollama request construction
- `Sources/PreferencesManager.swift` — `ollamaBaseURL` property

## Proposed Fix

Validate that `ollamaBaseURL` resolves to a loopback address before accepting it:

```swift
func isLoopbackURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString),
          let host = url.host else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
}
```

If the URL is not a loopback address:
1. Show a warning banner in the Ollama settings section.
2. Refuse to send text until the user explicitly acknowledges the risk with a confirmation dialog.

## Additional Context

This is not a theoretical risk — macOS apps are a common target for preferences-file manipulation by other malicious apps or scripts that run in the user's account.
