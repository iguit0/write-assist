# WriteAssist AGENTS

This file is the source of truth for contributor/agent behavior in this repo. Keep it grounded in current code and packaging scripts, not README/CLAUDE drift.

## Architecture + layout
- SwiftPM package with macOS 15 minimum and Swift 6 tools.
- Two targets:
  - **WriteAssistCore**: `Sources/` excluding `Sources/App/`. Contains business logic, services, AppKit/SwiftUI UI, resources, and persistence.
  - **WriteAssist**: executable shell in `Sources/App/`. Contains `WriteAssistApp`, `AppShellController`, `ReviewSelectionPanelController`, and `ReviewSelectionHotKeyController`.
- Tests live in `Tests/WriteAssistTests` and import **WriteAssistCore**.
- Keep product code under `Sources/`, grouped by current domains: `ReviewDomain/`, `ReviewServices/`, `ReviewWindow/`, `ReviewPanel/`, `Rewrite/`, `SystemIntegration/`, `WritingRules/`.
- Top-level `Sources/` files are shared core services/UI: AI, preferences, settings/about panels, status bar, AX helpers, persistence, spell/NL analysis, stats, and common models.
- Core session coordinators are:
  - `ReviewSessionStore` for document text, review lifecycle, analysis state, and workbench selections.
  - `RewriteSessionStore` for explicit rewrite lifecycle and candidate accept/reject.
  - `ReviewSelectionPanelStore` for selection-panel import/review/rewrite phase state.

## App flow + shell boundaries
- The app is launcher-first and accessory-policy based:
  - `WriteAssistApp.AppDelegate` creates `AppShellController`, `StatusBarController`, and `ReviewSelectionHotKeyController`.
  - `StatusBarController.setupLauncher(...)` owns the menu bar item/menu actions.
  - Menu action or global hotkey `Control+Option+Command+R` calls `AppShellController.triggerReviewSelection()`.
- `StatusBarController` is menu-only: no popover, no ambient monitors, no persistent global event monitor architecture.
- `AppShellController` owns AppKit window/panel controllers for workspace, selection review, settings, and about windows. Reuse those controllers instead of scattering window ownership.
- Workspace UI is SwiftUI (`ReviewWorkbenchView` and `ReviewWindow/` views) hosted in AppKit windows via `AppShellController`.
- Settings and About are SwiftUI views in the core target (`SettingsPanel`, `AboutPanel`) hosted by `AppShellController`.

## Concurrency + threading
- **Swift 6 strict concurrency**. Mutable app/session state lives on `@MainActor` stores, controllers, and observable services.
- Prefer `@MainActor` isolation and immutable snapshots over ad-hoc queue hopping.
- Keep staleness/cancellation guards when touching async flows, especially generation counters in `ReviewSessionStore` and `AppShellController`.
- `ReviewSessionStore.requestReview` uses a `Task` that remains main-actor aware for stale-result checks. Do not convert the whole review lifecycle to detached work.
- Use `Task.detached` only for immutable snapshotted CPU-bound work, currently `NLAnalysisService.analyze` inside `DeterministicReviewEngine`.
- `RuleRegistry.runAll(...disabledRules:)` is the nonisolated rule path for detached/snapshotted analysis. Do not read `PreferencesManager.shared` from nonisolated rule execution.
- `AXHelper` exposes `nonisolated static` helpers for AX reads; keep AX utility logic centralized there.
- `NSSpellChecker` access must stay main-actor mediated in `SpellCheckService`, using the async `requestChecking` path and the timeout guard.
- Carbon hotkey callbacks in `ReviewSelectionHotKeyController` must hop back to `@MainActor` before touching app state.

## Review + rewrite flow
- Mutate review text only through `ReviewSessionStore.replaceText` or `ReviewSessionStore.applyReplacement`.
- `ReviewSessionStore.requestReview` captures the document, runs `DeterministicReviewEngine`, then fills paragraph/sentence grouping through `ReviewGrouping.group` before publishing `.ready`.
- Selection import is one-shot via `SelectionImportService.importCurrentSelection()`; do not add persistent polling/observers.
- Selection import must skip WriteAssist itself, respect Accessibility permission, reject secure input/secure text fields through `AXHelper`, and include source-app metadata when available.
- Keep the launcher-first selection path:
  - status bar action/hotkey -> `AppShellController.triggerReviewSelection()`
  - AX anchor lookup -> `ReviewSelectionPanelController.show(anchorRect:)`
  - one-shot selection import -> `ReviewSelectionPanelStore.showImportedSelection(...)`
  - selected text is loaded into the panel review store with `autoReview: true`
- Selection-panel rewrite accept currently applies to source apps via pasteboard write plus synthetic `Cmd+V` in `AppShellController`; keep this behavior consistent unless intentionally redesigning replacement flow.
- Workbench rewrite accept must go through `RewriteSessionStore.acceptCandidate(...applying:)`, which delegates to `ReviewSessionStore.applyReplacement`.

## Writing rules
- Each rule lives in its own file in `Sources/WritingRules/` and conforms to `WritingRule`.
- Stable `ruleID` is required because preferences and issue identity depend on it.
- Add new rules to `RuleRegistry.allRules` or they will not run.
- Reuse `NLAnalysisService.analyze` output; do not create new NLP pipelines per rule.
- Word/phrase resources belong in `Sources/Resources/*.json`, loaded via `Bundle.module`. `Package.swift` already processes the whole `Resources` directory.
- Rule toggles are stored as `PreferencesManager.disabledRules`; use rule IDs as storage keys.

## AI + security
- Route provider calls through `CloudAIService`; do not add ad-hoc cloud API clients.
- `OllamaService` should remain behind `CloudAIService` / `LocalFirstRewriteEngine` boundaries.
- Keep prompt construction centralized in `AIPromptTemplates`.
- API keys must use `KeychainHelper` (`anthropic_api_key`, `openai_api_key`).
- Preserve TLS certificate pinning behavior in `CloudAIService` for Anthropic/OpenAI hosts.
- Preserve Ollama safety guard: only localhost/loopback URLs are allowed (`localhost`, `127.0.0.1`, `::1`).
- Rewrite provider policy is local-first in `LocalFirstRewriteEngine`: try configured Ollama when available/reachable, then fall back to a cloud provider.
- Cloud AI should remain explicit-user-action driven. Do not add passive background cloud review/rewrite calls.

## UI / AppKit boundary
- Selection review UI is a floating non-activating `NSPanel` (`ReviewSelectionPanelController`) anchored using AX selection bounds with screen-safe fallback positioning.
- Keep `ReviewSelectionPanelController` responsible for AppKit panel behavior; keep panel state and user actions in `ReviewSelectionPanelStore` / `ReviewSelectionPanelView`.
- Status item/menu icon resolves from `Sources/Resources/write-assist-menubar-template*.png` first, then SF Symbol fallback. Template menu bar assets must remain template-safe.
- About panel logos resolve from `write-assist-logo-dark.png` / `write-assist-logo-light.png` in `Sources/Resources` via `Bundle.module`.
- Use `SectionCardModifier` patterns in settings when updating settings UI, including the macOS 26 `glassEffect` fallback behavior.

## Persistence + singletons
- Reuse existing singletons/stores instead of adding new persistence layers: `PreferencesManager`, `IgnoreRulesStore`, `PersonalDictionary`, `WritingStatsStore`, `CloudAIService`.
- Keep storage keys and formats stable. If a format changes, add explicit migration behavior and tests.
- Current storage includes:
  - `UserDefaults`: preferences, disabled rules, provider/model settings, ignore rules, and legacy writing stats fallback.
  - Application Support JSON: personal dictionary and `writing-stats.json`.
  - Keychain: cloud provider API keys.
- `WritingStatsPersistence` migrates legacy `UserDefaults` sessions to Application Support JSON; preserve this migration path.

## Resources + packaging
- `Package.swift` processes `Sources/Resources` for the core bundle. Add runtime resources there when code loads them with `Bundle.module`.
- App bundle/release assets live under `assets/`, including `AppIcon.icns` and `Info.plist.template`.
- `scripts/build-app.sh` builds the universal release binary, assembles `build/WriteAssist.app`, copies the SwiftPM resource bundle and app icon, writes Info.plist, and ad-hoc signs.
- `scripts/make-icns.sh` regenerates `AppIcon.iconset` and `assets/AppIcon.icns` from installer-logo PNGs.
- `scripts/make-dmg.sh` packages the app and requires `create-dmg`.

## Logging + style
- Use `Logger(subsystem: "com.writeassist", category: "<Type>")` per file.
- Keep the standard file header style used across `Sources/` files.
- SwiftLint config disables `trailing_comma` and `line_length`, and opts into `empty_count` and `closure_spacing`.
- Default to small, focused changes. Do not rewrite app architecture or storage formats unless the task explicitly calls for it.

## Tests
- Tests use Swift **Testing** (`@Suite`, `@Test`) in `Tests/WriteAssistTests`.
- Import `WriteAssistCore` in tests.
- For writing-rule tests, prefer real `NLAnalysisService.analyze` coverage (see `WritingRuleTests.swift`).
- For persistence tests, prefer injected `UserDefaults(suiteName:)` and temporary file URLs instead of touching real user data.
- Run `swift test` for logic changes. For package/app shell changes, also run `swift build` when feasible.

## Docs / planning
- Current docs are sparse and live under `docs/` (currently CI/CD oriented). If docs disagree with code, follow the code.
- Keep AGENTS.md updated when architecture, app flow, resources, packaging, or persistence conventions change.

## Commit
Always follow the conventional commit pattern. Do not commit more than 160 characters.
