# `DocumentViewModel` is a 561-line God Object

**Labels:** `refactor` `architecture` `P2-medium`  
**Status:** 🆕 New

## Description

`DocumentViewModel` is the single `@Observable` hub for the entire application and has accumulated responsibilities far beyond a single view model:

- **Text buffering** — maintains `currentText`, `lastCheckText`, and `isProgrammaticBufferUpdate` flag
- **Check orchestration** — `runCheck()` races AI spell-check against a timeout, then falls back to NSSpellChecker, then merges NL analysis and rule engine results
- **State machine** — 5+ interrelated flags: `isCorrectionInFlight`, `lastCorrectionTime`, `hudShownKeys`, `recentlyCorrectedKeys`, `unseenIssueIDs`
- **AX injection** — calls C-level Accessibility API (`AXUIElementSetAttributeValue`)
- **Clipboard management** — writes/reads `NSPasteboard.general`
- **Writing metrics** — readability score, sentence count, syllable counts
- **Stat recording** — calls `WritingStatsStore.shared`
- **Issue deduplication** — `ignoredKey`, `hudShownKey`, `recentlyCorrected`

This makes `DocumentViewModel` untestable in isolation, hard to reason about, and prone to subtle state bugs when the multiple flags interact.

## Affected Files

- `Sources/DocumentViewModel.swift` (561 lines)

## Proposed Refactoring

Extract at minimum three collaborators:

1. **`CorrectionApplicator`** — owns AX injection + clipboard fallback + the `isCorrectionInFlight` / `recentlyCorrectedKeys` state
2. **`IssueGatekeeper`** — owns `hudShownKeys`, `unseenIssueIDs`, deduplication logic, and the `ignoredKey`/`hudShownKey` helpers
3. **`DocumentMetrics`** — a value type (struct) with readability, sentence count, syllable average; computed from the current text rather than stored as properties

`DocumentViewModel` then becomes a thin coordinator that holds these collaborators and exposes computed properties to the UI.

## Additional Context

The God Object problem also makes it impossible to write unit tests — the constructor has implicit dependencies on `CloudAIService.shared`, `PreferencesManager.shared`, `WritingStatsStore.shared`, etc. Extracting collaborators and injecting them via constructor parameters would unlock testability.
