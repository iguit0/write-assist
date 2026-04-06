# RW-602 — Quarantine legacy inline subsystems and clean docs

## Phase
Phase 6 — Legacy retirement

## Owner
Docs/tests/legacy-retirement agent

## Goal
Make it obvious in code and docs that the old inline-monitor architecture is no longer the primary product path.

## In scope
Update docs and quarantine notes for:
- `Sources/GlobalInputMonitor.swift`
- `Sources/SelectionMonitor.swift`
- `Sources/ExternalSpellChecker.swift`
- `Sources/ErrorHUDPanel.swift`
- `Sources/SelectionSuggestionPanel.swift`
- `Sources/SelectionSuggestionView.swift`
- `Sources/UndoToastPanel.swift`
- `Sources/GlobalKeyEventRouter.swift`
- AX writeback-heavy parts of `Sources/CorrectionApplicator.swift`
- `README.md`
- relevant docs under `docs/`

## Required outcomes
- Legacy inline files are clearly marked non-primary / quarantined.
- README reflects the review-workbench direction.
- Contributor-facing docs point to the new source-of-truth docs and ticket tree.

## Out of scope
- No broad product changes
- No startup ownership changes beyond documentation/cleanup support

## Dependencies
- RW-601

## Acceptance criteria
- [ ] README is aligned with the review-workbench product direction.
- [ ] Legacy inline files are documented as non-primary or quarantined.
- [ ] No new root markdown files are introduced.
- [ ] The docs point contributors to the new PRD/architecture/migration/ticket docs.

## Coordination notes
- If physical deletion is desired later, do it in a separate follow-up after the system is stable.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
