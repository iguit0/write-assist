# WriteAssist AGENTS

This file is the source of truth for contributor/agent behavior in this repo. It is grounded in the current code, not README/CLAUDE drift.

## Architecture + layout
- Two targets: **WriteAssistCore** (`Sources/` except `App/`) and **WriteAssist** (`Sources/App/`). Tests import **WriteAssistCore**.
- `Sources/App/` is executable-shell code (not just `WriteAssistApp.swift`): `WriteAssistApp`, `AppShellController`, review-selection panel controller, and global hotkey controller.
- Keep product code under `Sources/`, grouped by current domains:
  - `ReviewDomain/`, `ReviewServices/`, `ReviewWindow/`, `ReviewPanel/`, `Rewrite/`, `SystemIntegration/`, `WritingRules/`.
- Core session coordinators are:
  - `ReviewSessionStore` (document + analysis state)
  - `RewriteSessionStore` (rewrite lifecycle)
  - `ReviewSelectionPanelStore` (selection-panel phase + rewrite trigger state)

## Concurrency + threading
- **Swift 6 strict concurrency**. Mutable app/session state lives on `@MainActor` stores and services.
- Prefer `@MainActor` isolation and explicit state snapshots over ad-hoc queue hopping.
- Keep staleness/cancellation guards when touching async flows (generation counters in `ReviewSessionStore` and `AppShellController`).
- Use `Task.detached` only with immutable snapshotted inputs (`DeterministicReviewEngine` + `RuleRegistry.runAll(...disabledRules:)`).
- `AXHelper` exposes `nonisolated static` helpers for AX reads; keep AX utility logic centralized there.
- `NSSpellChecker` access must remain on the main actor (`SpellCheckService`), with timeout-protected async orchestration.

## Review + rewrite flow
- Mutate review text only through `ReviewSessionStore.replaceText` / `applyReplacement`.
- Selection import is one-shot via `SelectionImportService.importCurrentSelection()`; do not add persistent polling/observers.
- Keep the launcher-first flow:
  - status bar action/hotkey -> `AppShellController.triggerReviewSelection()`
  - import into selection panel store -> optional workspace handoff.
- Selection-panel rewrite accept currently applies to source apps via pasteboard write + synthetic Cmd+V in `AppShellController`; keep this behavior consistent unless intentionally redesigning replacement flow.

## Writing rules
- Each rule lives in its own file in `Sources/WritingRules/` and conforms to `WritingRule`.
- **Stable `ruleID` is required** (used by preferences and issue identity).
- Add new rules to `RuleRegistry.allRules` or they will not run.
- Reuse `NLAnalysisService.analyze` output; do not create new NLP pipelines per rule.
- Word/phrase resources belong in `Sources/Resources/*.json`, loaded via `Bundle.module`. Update `Package.swift` resources if needed.

## AI + security
- Route provider calls through `CloudAIService` (and `OllamaService` only through that boundary), not ad-hoc API clients.
- Keep prompt construction centralized in `AIPromptTemplates`.
- API keys must use `KeychainHelper`.
- Preserve TLS pinning behavior in `CloudAIService` for cloud providers.
- Preserve Ollama safety guard (`localhost` / loopback-only URL policy).
- Rewrite provider policy is local-first (`LocalFirstRewriteEngine`): try Ollama, then configured cloud fallback.

## UI / AppKit boundary
- Status item/menu is owned by `StatusBarController` in launcher mode (no popover/global monitor architecture).
- Selection review UI is a non-activating `NSPanel` (`ReviewSelectionPanelController`) anchored using AX selection bounds.
- Workspace UI is SwiftUI (`ReviewWorkbenchView` and related `ReviewWindow/` views) hosted in AppKit windows via `AppShellController`.

## Persistence + singletons
- Reuse existing singletons/stores instead of adding new persistence layers:
  - `PreferencesManager`, `IgnoreRulesStore`, `PersonalDictionary`, `WritingStatsStore`, `CloudAIService`.
- Keep storage keys and formats stable (`UserDefaults`, Application Support JSON files, keychain). If you must change format, add explicit migration behavior.

## Logging + style
- Use `Logger(subsystem: "com.writeassist", category: "<Type>")` per file.
- Keep the standard file header style used across `Sources/` files.
- SwiftLint config:
  - disabled: `trailing_comma`, `line_length`
  - opt-in: `empty_count`, `closure_spacing`

## Tests
- Tests live in `Tests/WriteAssistTests` and use Swift **Testing** (`@Suite`, `@Test`).
- Import `WriteAssistCore` in tests.
- For writing-rule tests, prefer real `NLAnalysisService.analyze` coverage (see `WritingRuleTests.swift`).

## Docs / planning
- Active product planning docs are currently under `tasks/`.
- `docs/` contains structure folders (`architecture/`, `plans/`, `superpowers/`) but may be sparse.
- If docs disagree with code, follow the code.

## Commit
Always follow conventional commit pattern. Do not commit more than 160 characters.
