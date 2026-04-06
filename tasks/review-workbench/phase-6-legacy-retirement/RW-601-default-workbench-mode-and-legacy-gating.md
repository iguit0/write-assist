# RW-601 — Make workbench mode the default and gate legacy startup

## Phase
Phase 6 — Legacy retirement

## Owner
Shell / legacy-retirement agent

## Goal
Stop treating the legacy inline system as the default startup path.

## In scope
Update:
- `Sources/App/WriteAssistApp.swift`
- `Sources/StatusBarController.swift`
- mode-gating points needed to keep legacy code compiling but secondary

## Required behavior
- Default mode becomes effectively `reviewWorkbenchOnly`.
- Legacy inline startup is behind explicit gating only.
- The app remains useful without starting ambient monitors.

## Out of scope
- No physical deletion of legacy files if that makes review harder.
- No new product features in legacy code.

## Dependencies
- RW-101
- RW-103
- RW-203
- RW-403
- RW-502

## Acceptance criteria
- [ ] Default startup path is the review workbench.
- [ ] Ambient monitor chain is no longer required for the core app path.
- [ ] Legacy inline path is clearly gated and non-primary.
- [ ] The app still builds and tests cleanly.

## Coordination notes
- High-conflict file ownership still applies here.
- Keep changes minimal and explicit.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
