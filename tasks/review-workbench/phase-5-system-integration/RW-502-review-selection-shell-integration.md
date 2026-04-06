# RW-502 — Wire Review Selection into the shell and launcher

## Phase
Phase 5 — System integration

## Owner
Shell/integrator agent

## Goal
Connect the one-shot selection import service to the review window and launcher-only menu bar mode.

## In scope
Update:
- `Sources/App/AppShellController.swift`
- `Sources/StatusBarController.swift`

## Required flow
1. trigger Review Selection
2. call `selectionImportService.importCurrentSelection()`
3. open/focus review window
4. route imported text into `ReviewSessionStore.replaceText(... autoReview: true)`
5. surface user-facing error/failure notice if import fails

## Out of scope
- No selection import AX implementation here
- No permanent monitor revival

## Dependencies
- RW-101
- RW-103
- RW-203
- RW-501

## Acceptance criteria
- [ ] Review Selection can be triggered from launcher mode.
- [ ] Imported text appears in the review window.
- [ ] Review auto-runs after import.
- [ ] Failures are surfaced without crashing or silently doing nothing.
- [ ] No permanent polling or monitor chain is introduced.

## Coordination notes
- Single-owner file: `Sources/StatusBarController.swift`
- Coordinate with shell owner only.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
