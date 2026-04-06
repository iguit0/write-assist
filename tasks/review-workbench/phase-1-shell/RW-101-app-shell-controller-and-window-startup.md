# RW-101 — Build `AppShellController` and cut startup toward the review workbench

## Phase
Phase 1 — Shell

## Owner
Shell/integrator agent

## Goal
Introduce a real app shell that owns the new workbench stores and startup behavior, then switch the default startup path toward the review workbench.

## In scope
Add or update:
- `Sources/App/AppShellController.swift`
- `Sources/App/WriteAssistApp.swift`

## Required responsibilities
`AppShellController` must own:
- `ReviewSessionStore`
- `RewriteSessionStore`
- launcher-facing `StatusBarController`
- `SelectionImporting`
- current `AppMode`

Add these shell-level capabilities:
- `start()`
- `stop()`
- `openReviewWindow()`
- `reviewSelection() async`
- `applyImportedSelection(_:)`
- `openSettings()`

## Startup rules
- Default app mode should move toward `reviewWorkbenchHybrid`.
- The app should no longer depend on the ambient monitor chain to be useful.
- Do not fully delete the legacy path yet.

## Out of scope
- No menu bar launcher implementation details here if that causes conflicts with RW-103.
- No deterministic review engine implementation.
- No rewrite engine implementation.

## Dependencies
- RW-001
- RW-002
- RW-003

## Acceptance criteria
- [ ] `AppShellController` exists and owns the new top-level stores/services.
- [ ] `WriteAssistApp` can boot the new shell.
- [ ] The app can open a review window path without requiring `GlobalInputMonitor` to be the product center.
- [ ] Legacy inline code remains compilable for fallback.

## Coordination notes
- Single-owner file: `Sources/App/WriteAssistApp.swift`
- Coordinate with RW-103 before changing menu bar startup behavior.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
