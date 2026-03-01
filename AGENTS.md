# WriteAssist AGENTS

This file is the source of truth for contributor/agent behavior in this repo. It is grounded in the current code, not README/CLAUDE drift.

## Architecture + layout
- Two targets: **WriteAssistCore** (Sources/ except App) and **WriteAssist** (Sources/App entry point). Tests import **WriteAssistCore**.
- AppKit + SwiftUI hybrid: menu-bar popover is SwiftUI; status item, HUD panels, selection panels, global monitors, and AX interactions are AppKit.
- DocumentViewModel (@Observable, @MainActor) is the coordinator for text buffer, checks, corrections, stats, and HUD gating.
- Keep new source under `Sources/`; only `WriteAssistApp.swift` lives in `Sources/App/`.

## Concurrency + threading
- **Swift 6 strict concurrency**. Mutable UI/state lives on `@MainActor` (see DocumentViewModel, SpellCheckService, etc.).
- Use `@preconcurrency import AppKit` where needed; prefer `@MainActor` over ad‑hoc dispatch.
- If you need background work, snapshot `@MainActor` state first, then pass immutable data into `Task.detached` or `nonisolated` helpers (see `RuleRegistry.runAll` overload).

## Writing rules
- Each rule is its own file in `Sources/WritingRules/` implementing `WritingRule`.
- **Stable `ruleID`** is required — used by preferences and ignore rules.
- Add new rules to `RuleRegistry.allRules` to make them active.
- Prefer `NLAnalysisService.analyze` output; do not recreate NLP pipelines per rule.
- Phrase lists or word pairs must live in `Sources/Resources/` JSON and load via `Bundle.module` (see `ConfusedWordRule`, `FormalityRule`, `InclusiveLanguageRule`). Update `Package.swift` if you add new resources.

## AI + spell check
- All AI calls go through `CloudAIService` (provider routing, TLS pinning, rate limiting, keychain storage). Don’t call OpenAI/Anthropic/Ollama directly.
- Generate prompts via `AIPromptTemplates` so tone/style stays centralized.
- API keys are stored via `KeychainHelper` only.
- `SpellCheckService` wraps `NSSpellChecker` with main-actor guard + timeout. Keep expensive work off the main thread, but do not touch NSSpellChecker from background threads.

## UI / AppKit boundary
- Status bar, HUD, selection panel, and global monitors are owned by `StatusBarController` and related panel classes. Avoid introducing new global monitors unless strictly necessary.
- HUD/selection panels are non‑activating `NSPanel`s anchored to caret bounds via AX APIs (`AXHelper`, `PanelPositioning`).
- Corrections use AX text replacement first, then clipboard+synthetic paste fallback. Keep this flow consistent.

## Persistence + singletons
- Preferences and stores are singletons: `PreferencesManager`, `IgnoreRulesStore`, `PersonalDictionary`, `WritingStatsStore`. Use existing stores instead of new persistence layers.
- Keep storage keys and on-disk formats stable; migrate explicitly if you must change them.

## Logging + style
- Use `Logger(subsystem: "com.writeassist", category: "<Type>")` per file.
- File header format is required:
  ```
  // WriteAssist — macOS menu bar writing assistant
  // Copyright © 2025 Igor Alves. All rights reserved.
  ```
- SwiftLint: `trailing_comma` and `line_length` are disabled; `empty_count` and `closure_spacing` are enabled. Don’t add code that violates the lint config.

## Tests
- Tests live in `Tests/WriteAssistTests` and use Swift **Testing** (`@Suite`, `@Test`).
- Import `WriteAssistCore` and use real `NLAnalysisService.analyze` for rule tests.

## Docs / known issues
- `docs/plans/` contains recent plans; `issues/` contains active pain points. Prefer aligning new changes to these constraints.
- If `CLAUDE.md` or `README.md` disagree with code, follow the code.
