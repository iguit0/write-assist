# Review Workbench Agent Tickets

This folder contains the concrete implementation tickets for the WriteAssist pivot from a system-wide inline assistant to a review-first, local-first rewrite workbench.

## Source-of-truth docs

Read these first:
- `tasks/prd-writeassist-review-workbench.md`
- `docs/architecture/review-workbench-target-architecture.md`
- `docs/plans/review-workbench-migration-plan.md`
- `docs/plans/review-workbench-orchestrated-implementation-plan.md`

## Execution rules

- New work goes into new folders first:
  - `Sources/ReviewDomain/`
  - `Sources/ReviewServices/`
  - `Sources/ReviewWindow/`
  - `Sources/Rewrite/`
  - `Sources/SystemIntegration/`
- Do not add new product behavior to legacy HUD / monitor / panel files.
- All local document mutations must go through `ReviewSessionStore.applyReplacement(...)`.
- Selection import must be one-shot only. No polling, no hidden monitors.

## Single-owner conflict files

Exactly one agent/integrator owns each of these during active work:
- `Sources/App/WriteAssistApp.swift`
- `Sources/StatusBarController.swift`
- `Sources/CloudAIService.swift`
- `Sources/SettingsPanel.swift`
- `Sources/PreferencesManager.swift` (if changed)
- `Sources/WritingIssue.swift` (if changed)

## Recommended execution order

### Batch 0 — Foundation (serial)
- `phase-0-foundation/RW-001-freeze-review-domain-contracts.md`
- `phase-0-foundation/RW-002-freeze-rewrite-and-import-contracts.md`
- `phase-0-foundation/RW-003-add-app-mode-and-placeholder-wiring.md`

### Batch 1 — Shell cutover + deterministic review (can overlap after Batch 0)
- `phase-1-shell/RW-101-app-shell-controller-and-window-startup.md`
- `phase-1-shell/RW-102-review-workbench-window-scaffold.md`
- `phase-1-shell/RW-103-launcher-only-status-bar-mode.md`
- `phase-2-review-engine/RW-201-deterministic-review-engine.md`
- `phase-2-review-engine/RW-202-review-grouping-and-snapshot-shaping.md`
- `phase-2-review-engine/RW-203-review-session-store-and-local-mutation-path.md`

### Batch 2 — Workbench UI (after Batch 1 contracts/store are merged)
- `phase-3-workbench-ui/RW-301-review-editor-view-bridge.md`
- `phase-3-workbench-ui/RW-302-grouped-review-sidebar.md`
- `phase-3-workbench-ui/RW-303-inspector-and-deterministic-actions.md`

### Batch 3 — Rewrite hero flow
- `phase-4-rewrite/RW-401-rewrite-contracts-and-store.md`
- `phase-4-rewrite/RW-402-local-first-rewrite-engine.md`
- `phase-4-rewrite/RW-403-rewrite-compare-ui-and-accept-flow.md`

### Batch 4 — External bridge
- `phase-5-system-integration/RW-501-one-shot-selection-import-service.md`
- `phase-5-system-integration/RW-502-review-selection-shell-integration.md`

### Batch 5 — Legacy quarantine
- `phase-6-legacy-retirement/RW-601-default-workbench-mode-and-legacy-gating.md`
- `phase-6-legacy-retirement/RW-602-legacy-inline-quarantine-and-doc-cleanup.md`

## Best first slices

### Slice 1
- RW-001
- RW-002
- RW-003
- RW-101
- RW-102
- RW-201
- RW-202
- RW-203

### Slice 2
- RW-301
- RW-302
- RW-303

### Slice 3
- RW-401
- RW-402
- RW-403

## Validation commands

These commands must pass for every ticket:
- `swift build`
- `swift test`
- `swiftlint`
