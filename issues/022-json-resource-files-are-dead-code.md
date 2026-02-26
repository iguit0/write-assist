# JSON resource files are excluded from the build and never loaded at runtime

**Labels:** `refactor` `documentation` `P2-medium`  
**Status:** 🆕 New

## Description

Three JSON files exist in `Sources/Resources/` but `Package.swift` explicitly excludes the entire `Resources/` directory from the build target:

```swift
// Package.swift
.executableTarget(
    name: "WriteAssist",
    path: "Sources",
    exclude: ["Resources"]  // ← these files are never bundled
)
```

The corresponding rules have their data hardcoded inline as Swift arrays:
- `Sources/Resources/confused-words.json` — data is hardcoded in `ConfusedWordRule.swift`
- `Sources/Resources/formality-words.json` — data is hardcoded in `FormalityRule.swift`
- `Sources/Resources/inclusive-language.json` — data is hardcoded in `InclusiveLanguageRule.swift`

The JSON files are dead code that suggests a resource-loading architecture that does not exist. New contributors may assume the JSON files are the source of truth and edit them, seeing no effect.

## Affected Files

- `Sources/Resources/confused-words.json`
- `Sources/Resources/formality-words.json`
- `Sources/Resources/inclusive-language.json`
- `Package.swift`

## Proposed Fix

Choose one of:

**Option A (simplest):** Delete the JSON files and document in the code comments that rule data is hardcoded inline. Remove the `exclude: ["Resources"]` line from `Package.swift` (or the entire `Resources/` directory).

**Option B (better long-term):** Use the JSON files as the canonical source of truth. Move them to a proper resource bundle (e.g., a `.bundle` resource target or by converting to a library target) and load them at runtime via `Bundle.module`. This makes the word lists editable without recompiling.

**Option C (build-time generation):** Add a Swift Package Manager build tool plugin that generates the Swift arrays from the JSON files at build time, giving compile-time safety with JSON editability.
