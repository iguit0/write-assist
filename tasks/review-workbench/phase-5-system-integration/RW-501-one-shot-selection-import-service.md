# RW-501 — Build one-shot selection import service

## Phase
Phase 5 — System integration

## Owner
System integration agent

## Goal
Provide a one-shot “Review Selection” import path without reintroducing permanent selection polling or ambient inline monitoring.

## In scope
Add:
- `Sources/SystemIntegration/SelectionImportService.swift`

Reuse carefully:
- `Sources/AXHelper.swift` (additive helpers only if needed)

## Required behavior
- Read current selection once from the focused app.
- Return `ImportedSelection` with metadata.
- Map failures into `SelectionImportError`.
- Handle secure contexts safely.

## Explicit anti-goals
Do not depend on:
- `Sources/SelectionMonitor.swift`
- `Sources/GlobalInputMonitor.swift`
- `Sources/ExternalSpellChecker.swift`

## Out of scope
- No launcher/menu bar wiring here
- No startup cutover

## Dependencies
- RW-002

## Acceptance criteria
- [ ] Selection import service compiles.
- [ ] It can import the current selection once.
- [ ] It returns the expected metadata shape.
- [ ] It maps secure-context and AX failure cases cleanly.
- [ ] It does not start background polling or monitoring.

## Coordination notes
- If AX helper additions are needed, keep them additive and isolated.
- Do not touch `StatusBarController.swift` in this ticket.

## Validation
- `swift build`
- `swift test`
- `swiftlint`
