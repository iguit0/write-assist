# RW-103 — Add launcher-only menu bar mode

## Phase
Phase 1 — Shell

## Owner
Shell/integrator agent

## Goal
Shrink the menu bar role to launcher-only behavior so it no longer represents the main product shell.

## In scope
Update:
- `Sources/StatusBarController.swift`

Add a launcher-only setup path, e.g.:
- `setupLauncher(onOpenReview:onReviewSelection:onOpenSettings:)`

## Required launcher actions
- Open Review
- Review Selection
- Settings
- Quit

## Behavioral constraints
- Do not start `SelectionMonitor` in launcher mode.
- Do not create `ExternalSpellChecker` in launcher mode.
- Do not create HUD/selection/undo panels in launcher mode.
- Do not use badge observation tied to ambient typing in launcher mode.

## Recommended implementation
Use `NSMenu` instead of adding another SwiftUI menu-bar popover.

## Out of scope
- No one-shot selection import service implementation here.
- No startup ownership changes beyond what RW-101 coordinates.

## Dependencies
- RW-101

## Acceptance criteria
- [ ] `StatusBarController` has a launcher-only mode.
- [ ] Launcher mode exposes the four required actions.
- [ ] Launcher mode does not spin up legacy inline-monitor subsystems.
- [ ] Legacy setup path still compiles for fallback while migration is in progress.

## Coordination notes
- Single-owner file: `Sources/StatusBarController.swift`
- Coordinate closely with RW-101 and RW-502.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
