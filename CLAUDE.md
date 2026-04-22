# WriteAssist

macOS menu bar writing assistant — review-and-rewrite workbench for non-native English speakers.

## Build & Lint

- `swift build` — compile (must pass with zero errors/warnings)
- `swift run` — build and launch (appears as pencil icon in menu bar, not Dock)
- `swiftlint` — lint (must pass with zero violations)
- `swift test` — run unit tests (must pass)
- Tests use Swift Testing framework (`import Testing`, `@Test`, `#expect`) — not XCTest
- Test target imports `@testable import WriteAssistCore`

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
- JSON resources in `Sources/Resources/` (excluded from target in Package.swift, loaded at runtime)
- `ReviewSelectionHotKeyController` registers a global Carbon hotkey to trigger review selection
- `ReviewSelectionPanelController` manages the floating review-selection panel NSWindow

## State Ownership

- `ReviewSessionStore` — document text, analysis snapshot, selected issue/paragraph/sentence, analysis lifecycle
- `RewriteSessionStore` — rewrite target, mode, candidates, provider metadata
- `AppShellController` — window focus, menu bar lifecycle, selection import entry point
- `ReviewSelectionPanelStore` — selection panel phase (idle/importing/error/review), imported selection

## Code Style

- File header: `// WriteAssist — macOS menu bar writing assistant` + copyright line
- SwiftLint: `trailing_comma` and `line_length` disabled; `empty_count` and `closure_spacing` opted in
- Logger subsystem: `com.writeassist`

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
