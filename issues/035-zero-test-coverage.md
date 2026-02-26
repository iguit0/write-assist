# Zero test coverage — no test target in `Package.swift`

**Labels:** `testing` `P1-high`  
**Status:** 🆕 New

## Description

The Swift package has a single `executableTarget` and zero test targets. There are no unit tests, integration tests, or snapshot tests for any component in the codebase. Many components contain fragile logic that has already produced bugs found in code review:

- `CloudAIService.parseSpellCheckResponse` — parses freeform AI text output for JSON; highly likely to fail on edge cases
- All 11 `WritingRule.check` implementations — complex string/NL logic with multiple known bugs already
- `ExternalSpellChecker.readWordBeforeCursor` — cursor-edge cases (start/end of document, contractions)
- `DocumentViewModel` ignore/correction/dedup key logic — multiple interacting state flags
- `NLAnalysisService.countSyllables` — known edge cases with silent-e, `-le` endings

Without tests, every fix creates a risk of regression in another part of the system.

## Proposed Fix

### Step 1: Add the test target to `Package.swift`

```swift
.testTarget(
    name: "WriteAssistTests",
    dependencies: ["WriteAssist"],
    path: "Tests"
)
```

> **Note:** An `executableTarget` cannot be imported by a test target. Refactor the app entry point so the bulk of the code lives in a `library` target (`WriteAssistCore`) that the executable imports. Tests then import `WriteAssistCore`.

### Step 2: Write the highest-value tests first

Priority order (biggest risk reduction per test written):

1. **`CloudAIServiceTests`** — `parseSpellCheckResponse` with truncated JSON, code-fenced JSON, empty response, invalid issue types
2. **`WritingRuleTests`** — each of the 11 rules: empty text, single word, Unicode input, HTML tags, code snippets, duplicate sentences
3. **`ExternalSpellCheckerTests`** — `extractWordBefore` at cursor positions: start of document, end of document, mid-word, after punctuation, contractions (`don't`, `it's`)
4. **`NLAnalysisServiceTests`** — `countSyllables` edge cases: silent-e words, `-le` endings, one-syllable words, empty string
5. **`DocumentViewModelTests`** — ignore key generation, deduplication logic, issue filtering by category

## Additional Context

The lack of a test target also makes it impossible to use `swift test` in CI, which means regressions in the rule engine or AI parsing can ship silently.
