# AI model names are hardcoded — users cannot select model

**Labels:** `enhancement` `P2-medium`  
**Status:** 🆕 New

## Description

The Anthropic and OpenAI model names are hardcoded constants in `CloudAIService.swift`:

```swift
// CloudAIService.swift
let model = "claude-sonnet-4-20250514"   // Anthropic
let model = "gpt-4o-mini"                // OpenAI
```

This creates two problems:

1. **User choice:** users with different API tiers (GPT-4o, Claude Haiku, Claude Opus) have no way to select a cheaper or more capable model.
2. **Model deprecation:** when OpenAI or Anthropic deprecates the hardcoded model, the app will silently send requests to a deprecated endpoint or return errors until a new version is shipped.

## Affected Files

- `Sources/CloudAIService.swift` — model name constants, approximately lines 294 and 365
- `Sources/PreferencesManager.swift` — needs new preference properties
- `Sources/ContentView.swift` — Settings panel needs model selection UI

## Proposed Fix

Add model name preferences with sensible defaults:

```swift
// PreferencesManager.swift
@AppStorage("anthropicModelName") var anthropicModelName: String = "claude-sonnet-4-20250514"
@AppStorage("openAIModelName") var openAIModelName: String = "gpt-4o-mini"
```

Expose as text fields (or picker menus) in the Settings panel alongside the API key fields. Display a warning if the model name doesn't match a known good format.

## Additional Context

A curated list of valid model identifiers (fetched from the provider's `/models` endpoint or hardcoded as an enum) would improve the UX over a free-text field.
