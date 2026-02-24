# WriteAssist

macOS menu bar writing assistant — offline spelling & grammar checker using NSSpellChecker.

## Build & Lint

- `swift build` — compile (must pass with zero errors/warnings)
- `swift run` — build and launch (appears as pencil icon in menu bar, not Dock)
- `swiftlint` — lint (must pass with zero violations)
- No test target exists yet

## Architecture

- **Swift 6 strict concurrency** — uses `@MainActor`, `@preconcurrency import`, `@unchecked Sendable`
- **MVVM** — `DocumentViewModel` (`@Observable`) is the central hub
- **AppKit + SwiftUI hybrid** — menu bar popover is SwiftUI; floating HUD, status bar, and global event monitoring are AppKit
- **Menu bar app** — activation policy `.accessory`, no Dock icon, no main window; `Settings { EmptyView() }` prevents "No scene found" warning
- **No external dependencies** — SPM project, single executable target

## Key Patterns

- `GlobalInputMonitor` captures keystrokes via `NSEvent.addGlobalMonitorForEvents`
- `SpellCheckService` wraps `NSSpellChecker` with 800ms timeout guard
- `ErrorHUDPanel` is a non-activating `NSPanel` positioned near the text caret via Accessibility API
- Corrections applied in-place via `AXUIElementSetAttributeValue`; falls back to clipboard + synthetic Cmd+V
- Writing rules in `Sources/WritingRules/` — each is a separate rule file
- JSON resources in `Sources/Resources/` (excluded from target in Package.swift, loaded at runtime)

## Code Style

- File header: `// WriteAssist — macOS menu bar writing assistant` + copyright line
- SwiftLint: `trailing_comma` and `line_length` disabled; `empty_count` and `closure_spacing` opted in
- Logger subsystem: `com.writeassist`

## Project Layout

- `Sources/` — all Swift source files (flat, no subdirectories except WritingRules/)
- `Sources/WritingRules/` — individual rule implementations
- `Sources/Resources/` — JSON data files for rules
- `tasks/prd-writeassist.md` — product requirements document
