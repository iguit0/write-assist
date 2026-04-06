# RW-003 — Add app mode and placeholder wiring

## Phase
Phase 0 — Foundation

## Owner
Shell/integrator agent

## Goal
Create compile-safe placeholders and an app-mode switch so later PRs can wire the new stack without fighting startup immediately.

## In scope
Add or update:
- `Sources/App/AppMode.swift`
- placeholder/no-op implementations as needed for:
  - review engine
  - rewrite engine
  - selection import service

## Required app modes
- `.legacyInline`
- `.reviewWorkbenchHybrid`
- `.reviewWorkbenchOnly`

## Required placeholder behavior
- The app must compile with the new contracts even if the real engine/UI are not wired yet.
- Placeholder services may be no-op, preview, or stub implementations.
- No placeholder should start background monitors.

## Out of scope
- No real startup cutover
- No window shell
- No real engine behavior

## Dependencies
- RW-001
- RW-002

## Acceptance criteria
- [ ] `AppMode` exists and compiles.
- [ ] Placeholder services compile against the frozen contracts.
- [ ] No startup behavior changes yet beyond compile-safe scaffolding.
- [ ] No new logic is added to the legacy inline path.

## Coordination notes
- Keep this additive.
- Do not modify `StatusBarController.setup(viewModel:inputMonitor:)` behavior yet.
- This ticket exists to unblock other workstreams.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
