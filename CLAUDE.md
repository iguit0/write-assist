# WriteAssist

macOS menu bar writing assistant — review-and-rewrite workbench for non-native English speakers.

See `AGENTS.md` for full contributor/agent conventions (concurrency rules, AI routing, packaging) — this file is a digest.

## Build & Lint

- `swift build` — compile (must pass with zero errors/warnings)
- `swift run` — build and launch (appears as pencil icon in menu bar, not Dock)
- `swiftlint` — lint (must pass with zero violations)
- `swift test` — run unit tests (must pass)
- Tests use Swift Testing framework (`import Testing`, `@Test`, `#expect`) — not XCTest
- Test target imports `@testable import WriteAssistCore`
- `scripts/build-app.sh <version>` — assemble universal `.app` bundle (ad-hoc signed)
- `scripts/make-dmg.sh <version>` — package `.app` into DMG (requires `brew install create-dmg`)
- `scripts/make-icns.sh` — regenerate `AppIcon.icns` from PNGs in `assets/`
- `VERSION` file must match release tag's base (e.g. `v0.1.0` or `v0.1.0-preview.1`)
- Global hotkey for "Review Selection": `Control+Option+Command+R`

## Architecture

- **Swift 6 strict concurrency** — uses `@MainActor`, `@preconcurrency import`, `@unchecked Sendable`
- **Review Workbench** — primary product surface; a main NSWindow with editor, grouped review results, inspector, and rewrite compare panel
- **AppKit + SwiftUI hybrid** — review window is SwiftUI hosted in NSWindow; status bar is AppKit
- **Menu bar as launcher only** — activation policy `.accessory`, no Dock icon; status item opens the review window via NSMenu (no popover)
- **No external dependencies** — SPM project; `WriteAssistCore` library + thin `WriteAssist` executable
- **macOS 15+** — minimum deployment target; Swift Testing for unit tests (not XCTest)
- **Observation framework** — stores use `@Observable` macro, not `ObservableObject`

## Key Patterns

- `AppShellController` owns the review window lifecycle, selection import, and settings routing
- `ReviewSessionStore` is the single source of truth for the review document, analysis state, and issue/paragraph selection
- `RewriteSessionStore` owns rewrite targets, candidates, and provider state
- `DeterministicReviewEngine` wraps `SpellCheckService`, `NLAnalysisService`, `RuleEngine`, and `WritingRules/*`; produces a `ReviewAnalysisSnapshot` keyed by `documentRevision`
- `SelectionImportService` is a one-shot AX import — no background polling
- Writing rules in `Sources/WritingRules/` — each is a separate rule file
- Resources in `Sources/Resources/` are processed by SPM (`resources: [.process("Resources")]`) and loaded at runtime via `Bundle.module`
- `ReviewSelectionHotKeyController` registers a global Carbon hotkey to trigger review selection
- `ReviewSelectionPanelController` manages the floating review-selection panel NSWindow
- New writing rules **must** be registered in `RuleRegistry.allRules`, or they won't run
- Mutate review text only via `ReviewSessionStore.replaceText` / `applyReplacement` — never write to the document directly
- Selection-panel rewrite accept applies to the source app via pasteboard write + synthetic `Cmd+V` in `AppShellController`
- Do **not** read `PreferencesManager.shared` from nonisolated rule execution (`RuleRegistry.runAll`)

## State Ownership

- `ReviewSessionStore` — document text, analysis snapshot, selected issue/paragraph/sentence, analysis lifecycle
- `RewriteSessionStore` — rewrite target, mode, candidates, provider metadata
- `AppShellController` — window focus, menu bar lifecycle, selection import entry point
- `ReviewSelectionPanelStore` — selection panel phase (idle/importing/error/review), imported selection

## Code Style

- File header: `// WriteAssist — macOS menu bar writing assistant` + copyright line
- SwiftLint: `trailing_comma` and `line_length` disabled; `empty_count` and `closure_spacing` opted in
- Logger subsystem: `com.writeassist`
- Commits: conventional commits, message ≤160 chars

## AI & Security

- All cloud provider calls route through `CloudAIService`; prompts via `AIPromptTemplates` — no ad-hoc clients
- API keys via `KeychainHelper` with keys `anthropic_api_key` / `openai_api_key`
- `OllamaService` rejects non-localhost URLs (`localhost`, `127.0.0.1`, `::1` only)
- `CloudAIService` enforces TLS certificate pinning for Anthropic/OpenAI hosts — preserve this
- Cloud AI is explicit-user-action only; do not add passive background cloud calls

## Project Layout

- `Sources/App/` — executable entry point (`WriteAssistApp`, `AppShellController`)
- `Sources/ReviewDomain/` — `ReviewDocument`, `ReviewSessionStore`, analysis snapshots
- `Sources/ReviewServices/` — `DeterministicReviewEngine`, `ReviewGrouping`
- `Sources/ReviewWindow/` — workbench UI: editor, paragraph list, inspector, rewrite compare
- `Sources/Rewrite/` — `RewriteEngine`, `LocalFirstRewriteEngine`, `RewriteSessionStore`, request/candidate types
- `Sources/ReviewPanel/` — floating review-selection panel (`ReviewSelectionPanelStore`, `ReviewSelectionPanelView`)
- `Sources/SystemIntegration/` — one-shot `SelectionImportService`
- `Sources/WritingRules/` — individual deterministic rule implementations
- `Sources/Resources/` — JSON data files for rules
